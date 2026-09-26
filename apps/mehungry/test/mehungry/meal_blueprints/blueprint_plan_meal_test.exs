defmodule Mehungry.MealBlueprints.BlueprintPlanMealTest do
  use Mehungry.DataCase, async: true

  alias Mehungry.MealBlueprints.BlueprintPlanMeal
  alias Mehungry.MealBlueprints.BlueprintPlanMealIngredient

  defp ingredient_params(extra) do
    Map.merge(%{"ingredient_id" => 5, "quantity" => 2.0}, extra)
  end

  describe "BlueprintPlanMealIngredient unit_selection decode" do
    test "a positive value resolves to a measurement unit" do
      cs =
        BlueprintPlanMealIngredient.changeset(
          %BlueprintPlanMealIngredient{},
          ingredient_params(%{"unit_selection" => "7"})
        )

      assert Ecto.Changeset.get_field(cs, :measurement_unit_id) == 7
      assert Ecto.Changeset.get_field(cs, :ingredient_portion_id) == nil
    end

    test "a negative value resolves to a description-only portion" do
      cs =
        BlueprintPlanMealIngredient.changeset(
          %BlueprintPlanMealIngredient{},
          ingredient_params(%{"unit_selection" => "-3"})
        )

      assert Ecto.Changeset.get_field(cs, :ingredient_portion_id) == 3
      assert Ecto.Changeset.get_field(cs, :measurement_unit_id) == nil
    end

    test "a blank value is dropped (no spurious cast error)" do
      cs =
        BlueprintPlanMealIngredient.changeset(
          %BlueprintPlanMealIngredient{},
          ingredient_params(%{"unit_selection" => ""})
        )

      assert cs.valid?
      refute Keyword.has_key?(cs.errors, :unit_selection)
    end
  end

  describe "BlueprintPlanMealIngredient.unit_selection_value/1" do
    test "returns the measurement_unit_id for a unit-bearing row" do
      row = %BlueprintPlanMealIngredient{measurement_unit_id: 9}
      assert BlueprintPlanMealIngredient.unit_selection_value(row) == 9
    end

    test "returns -portion_id for a description-only portion" do
      row = %BlueprintPlanMealIngredient{measurement_unit_id: nil, ingredient_portion_id: 4}
      assert BlueprintPlanMealIngredient.unit_selection_value(row) == -4
    end
  end

  describe "recipe-or-ingredients validation" do
    defp meal_params(extra) do
      Map.merge(
        %{"day_index" => 1, "meal_type" => "breakfast", "blueprint_plan_id" => 1},
        extra
      )
    end

    test "a recipe-only meal is valid" do
      cs = BlueprintPlanMeal.changeset(%BlueprintPlanMeal{}, meal_params(%{"recipe_id" => 3}))
      assert cs.valid?
    end

    test "an ingredient-only meal is valid" do
      cs =
        BlueprintPlanMeal.changeset(
          %BlueprintPlanMeal{},
          meal_params(%{"ingredients" => [%{"ingredient_id" => 5, "quantity" => 2.0}]})
        )

      assert cs.valid?
    end

    test "a meal with a recipe and ingredients is valid" do
      cs =
        BlueprintPlanMeal.changeset(
          %BlueprintPlanMeal{},
          meal_params(%{
            "recipe_id" => 3,
            "ingredients" => [%{"ingredient_id" => 5, "quantity" => 2.0}]
          })
        )

      assert cs.valid?
    end

    test "a meal with neither a recipe nor an ingredient is invalid" do
      cs = BlueprintPlanMeal.changeset(%BlueprintPlanMeal{}, meal_params(%{}))
      refute cs.valid?
      assert {"a plan meal needs a recipe or at least one ingredient", _} = cs.errors[:recipe_id]
    end
  end
end
