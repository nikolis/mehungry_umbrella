defmodule Mehungry.MealBlueprints.BlueprintPlanMealTest do
  use Mehungry.DataCase, async: true

  alias Mehungry.MealBlueprints.BlueprintPlanMeal

  defp base_params(extra) do
    Map.merge(
      %{
        "day_index" => 1,
        "meal_type" => "breakfast",
        "blueprint_plan_id" => 1,
        "ingredient_id" => 5,
        "quantity" => 2.0
      },
      extra
    )
  end

  describe "unit_selection decode" do
    test "a positive value resolves to a measurement unit" do
      cs =
        BlueprintPlanMeal.changeset(%BlueprintPlanMeal{}, base_params(%{"unit_selection" => "7"}))

      assert Ecto.Changeset.get_field(cs, :measurement_unit_id) == 7
      assert Ecto.Changeset.get_field(cs, :ingredient_portion_id) == nil
    end

    test "a negative value resolves to a description-only portion" do
      cs =
        BlueprintPlanMeal.changeset(
          %BlueprintPlanMeal{},
          base_params(%{"unit_selection" => "-3"})
        )

      assert Ecto.Changeset.get_field(cs, :ingredient_portion_id) == 3
      assert Ecto.Changeset.get_field(cs, :measurement_unit_id) == nil
    end

    test "a blank value is dropped (no spurious cast error)" do
      cs =
        BlueprintPlanMeal.changeset(%BlueprintPlanMeal{}, base_params(%{"unit_selection" => ""}))

      assert cs.valid?
      refute Keyword.has_key?(cs.errors, :unit_selection)
    end
  end

  describe "unit_selection_value/1" do
    test "returns the measurement_unit_id for a unit-bearing row" do
      assert BlueprintPlanMeal.unit_selection_value(%BlueprintPlanMeal{measurement_unit_id: 9}) ==
               9
    end

    test "returns -portion_id for a description-only portion" do
      meal = %BlueprintPlanMeal{measurement_unit_id: nil, ingredient_portion_id: 4}
      assert BlueprintPlanMeal.unit_selection_value(meal) == -4
    end
  end
end
