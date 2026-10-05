defmodule Mehungry.MealBlueprints.DietPatternsTest do
  use Mehungry.DataCase, async: true

  import Mehungry.AccountsFixtures

  alias Mehungry.MealBlueprints
  alias Mehungry.MealBlueprints.DietPatterns
  alias Mehungry.History.MealType

  test "exposes the two diet-pattern descriptors with unique names" do
    patterns = DietPatterns.all()
    assert length(patterns) == 2
    assert DietPatterns.keys() == [:mediterranean, :low_fodmap]

    names = Enum.map(patterns, & &1.name)
    assert names == ["Mediterranean Diet", "Low-FODMAP Diet"]
    assert length(Enum.uniq(names)) == 2
  end

  test "each pattern builds a valid, insertable blueprint with the expected shape" do
    user = user_fixture()

    for key <- DietPatterns.keys() do
      case DietPatterns.create_for_user(user.id, key) do
        {:ok, bp} ->
          bp = MealBlueprints.get_blueprint!(user.id, bp.id)

          # 7 days × 5 canonical slots.
          assert length(bp.days) == 7

          for day <- bp.days do
            slots = Enum.map(day.meals, & &1.meal_type)
            assert Enum.sort(slots) == Enum.sort(MealType.values())

            for meal <- day.meals do
              assert meal.protein_pct + meal.carbs_pct + meal.fats_pct == 100
            end
          end

          MealBlueprints.delete_blueprint(bp)

        {:error, changeset} ->
          flunk("pattern #{key} invalid: #{inspect(errors_on(changeset))}")
      end
    end
  end

  test "Mediterranean is an encourage pattern (nutrients/compounds, no avoid foods)" do
    med = DietPatterns.get(:mediterranean)

    assert "Omega-3" in med.required_nutrients
    assert "Polyphenols" in med.required_compounds
    assert "Saturated Fat" in med.avoid_nutrients
    assert "olive oil" in med.preferred_foods
    assert med.avoid_foods == []
  end

  test "Low-FODMAP is an avoidance pattern driven by avoid_foods + FODMAP compound" do
    fodmap = DietPatterns.get(:low_fodmap)

    assert "FODMAP" in fodmap.avoid_compounds
    assert "onion" in fodmap.avoid_foods
    assert "garlic" in fodmap.avoid_foods
    assert "wheat" in fodmap.avoid_foods
    assert "rice" in fodmap.preferred_foods
  end

  test "attrs_for carries avoid_foods through to the created blueprint" do
    user = user_fixture()
    {:ok, bp} = DietPatterns.create_for_user(user.id, :low_fodmap)

    assert "onion" in bp.avoid_foods
    assert "garlic" in bp.avoid_foods
  end

  test "creates a self-contained blueprint with no backing condition" do
    user = user_fixture()
    {:ok, bp} = DietPatterns.create_for_user(user.id, :mediterranean)
    assert is_nil(bp.condition_id)
  end

  describe "create_missing_for_user/1" do
    test "creates all patterns the first time, none the second (idempotent by name)" do
      user = user_fixture()

      assert {:ok, 2} = DietPatterns.create_missing_for_user(user.id)
      assert {:ok, 0} = DietPatterns.create_missing_for_user(user.id)

      names =
        user.id |> MealBlueprints.list_blueprints_for_user() |> Enum.map(& &1.name) |> Enum.sort()

      assert names == ["Low-FODMAP Diet", "Mediterranean Diet"]
    end
  end
end
