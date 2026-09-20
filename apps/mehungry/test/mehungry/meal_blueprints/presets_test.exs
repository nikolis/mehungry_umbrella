defmodule Mehungry.MealBlueprints.PresetsTest do
  use Mehungry.DataCase, async: true

  import Mehungry.AccountsFixtures

  alias Mehungry.MealBlueprints
  alias Mehungry.MealBlueprints.Presets
  alias Mehungry.History.MealType

  test "covers all 36 sex × activity × age combinations with unique names" do
    presets = Presets.all()
    assert length(presets) == 2 * 3 * 6

    names = Enum.map(presets, & &1.name)
    assert length(Enum.uniq(names)) == length(names)
  end

  test "names are descriptive (sex, age band, activity, calories)" do
    p = Presets.get(:female, :regular, 30)
    assert p.name == "Female · 30s · Regular exercise (2200 kcal/day)"
  end

  test "every preset builds a valid, insertable blueprint" do
    user = user_fixture()

    for preset <- Presets.all() do
      attrs = Presets.attrs_for(preset, user.id)

      case MealBlueprints.create_blueprint(attrs) do
        {:ok, bp} ->
          # Clean up so the 36 inserts don't collide on the unique day/meal indexes.
          MealBlueprints.delete_blueprint(bp)

        {:error, changeset} ->
          flunk("preset #{preset.key} invalid: #{inspect(errors_on(changeset))}")
      end
    end
  end

  test "a preset yields 7 days × 5 canonical meal slots with sane targets" do
    user = user_fixture()
    {:ok, bp} = Presets.create_for_user(user.id, :male, :some, 40)
    loaded = MealBlueprints.get_blueprint!(user.id, bp.id)

    assert length(loaded.days) == 7
    assert Enum.all?(loaded.days, &(&1.total_calorie_target == 2600))

    for day <- loaded.days do
      assert Enum.map(day.meals, & &1.meal_type) == MealType.values()

      for meal <- day.meals do
        assert meal.protein_pct + meal.carbs_pct + meal.fats_pct == 100
        assert Enum.all?([meal.protein_pct, meal.carbs_pct, meal.fats_pct], &(&1 >= 0))
      end
    end
  end

  test "blueprint-level required nutrients and preferred foods; meals/days carry no general targets" do
    p = Presets.get(:female, :regular, 30)

    assert "Vitamin C" in p.required_nutrients
    assert "eggs" in p.preferred_foods
    assert p.required_compounds == []
    assert p.avoid_nutrients == []
    assert p.avoid_compounds == []

    # Days carry only calorie + meals; meals carry only macros.
    day = hd(p.days)
    refute Map.has_key?(day, :required_nutrients)
    meal = hd(day.meals)
    refute Map.has_key?(meal, :required_nutrients)
    refute Map.has_key?(meal, :preferred_foods)
  end

  test "life-stage requirements: reproductive-age women get iron/folate at the blueprint level" do
    p = Presets.get(:female, :none, 30)
    assert "Iron" in p.required_nutrients
    assert "Folate" in p.required_nutrients
  end

  test "life-stage requirements: older adults get B12/Vitamin D at the blueprint level" do
    p = Presets.get(:male, :regular, 70)
    assert "Vitamin B12" in p.required_nutrients
    assert "Vitamin D" in p.required_nutrients
  end

  test "life-stage requirements are cumulative: a 60s woman gets bone-health and older-adult sets" do
    p = Presets.get(:female, :some, 60)
    assert "Calcium" in p.required_nutrients
    assert "Vitamin B12" in p.required_nutrients
    assert "Vitamin D" in p.required_nutrients
    # No duplicate Vitamin D even though two life-stage sets include it.
    assert Enum.count(p.required_nutrients, &(&1 == "Vitamin D")) == 1
  end
end
