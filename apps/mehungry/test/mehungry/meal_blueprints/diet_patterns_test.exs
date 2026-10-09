defmodule Mehungry.MealBlueprints.DietPatternsTest do
  use Mehungry.DataCase, async: true

  import Mehungry.AccountsFixtures

  alias Mehungry.MealBlueprints
  alias Mehungry.MealBlueprints.DietPatterns
  alias Mehungry.History.MealType

  @expected_keys [
    :mediterranean,
    :low_fodmap,
    :ketogenic,
    :low_carb,
    :high_protein,
    :low_fat,
    :zone,
    :atkins,
    :dash,
    :mind,
    :nordic,
    :whole_food_plant_based,
    :vegan,
    :vegetarian,
    :pescatarian,
    :paleo,
    :whole30,
    :gluten_free,
    :dairy_free,
    :low_sodium,
    :low_glycemic
  ]

  @expected_names [
    "Mediterranean Diet",
    "Low-FODMAP Diet",
    "Ketogenic Diet",
    "Low-Carb Diet",
    "High-Protein Diet",
    "Low-Fat Diet",
    "Zone Diet",
    "Atkins Diet",
    "DASH Diet",
    "MIND Diet",
    "Nordic Diet",
    "Whole-Food Plant-Based Diet",
    "Vegan Diet",
    "Vegetarian Diet",
    "Pescatarian Diet",
    "Paleo Diet",
    "Whole30 Diet",
    "Gluten-Free Diet",
    "Dairy-Free Diet",
    "Low-Sodium Diet",
    "Low-Glycemic Diet"
  ]

  test "exposes every diet-pattern descriptor with unique names" do
    patterns = DietPatterns.all()
    assert length(patterns) == 21
    assert DietPatterns.keys() == @expected_keys

    names = Enum.map(patterns, & &1.name)
    assert names == @expected_names
    assert length(Enum.uniq(names)) == 21
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

  test "Ketogenic is a very-low-carb, high-fat macro pattern" do
    keto = DietPatterns.get(:ketogenic)
    macro = keto.days |> hd() |> Map.get(:meals) |> hd()

    assert {macro.protein_pct, macro.carbs_pct, macro.fats_pct} == {20, 5, 75}
    assert "bread" in keto.avoid_foods
    assert "sugar" in keto.avoid_foods
  end

  test "Vegan is an avoidance pattern excluding all animal products" do
    vegan = DietPatterns.get(:vegan)

    assert "meat" in vegan.avoid_foods
    assert "dairy" in vegan.avoid_foods
    assert "eggs" in vegan.avoid_foods
    assert "honey" in vegan.avoid_foods
    assert "legumes" in vegan.preferred_foods
  end

  test "DASH is an encourage pattern using only resolving nutrient tags" do
    dash = DietPatterns.get(:dash)

    assert "Fiber" in dash.required_nutrients
    assert "Sodium" in dash.avoid_nutrients
    assert "Saturated Fat" in dash.avoid_nutrients
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

      assert {:ok, 21} = DietPatterns.create_missing_for_user(user.id)
      assert {:ok, 0} = DietPatterns.create_missing_for_user(user.id)

      names =
        user.id |> MealBlueprints.list_blueprints_for_user() |> Enum.map(& &1.name) |> Enum.sort()

      assert names == Enum.sort(@expected_names)
    end
  end
end
