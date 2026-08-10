defmodule Mehungry.NutrientUtilsTest do
  use ExUnit.Case, async: true

  alias Mehungry.NutrientUtils, as: Nu

  describe "to_grams/2" do
    test "keeps grams unchanged" do
      assert {:ok, 20.0} = Nu.to_grams(20, "g")
      assert {:ok, 20.0} = Nu.to_grams(20, "grams")
    end

    test "converts milligrams to grams" do
      assert {:ok, grams} = Nu.to_grams(500, "mg")
      assert_in_delta grams, 0.5, 1.0e-9
    end

    test "converts micrograms to grams (µg / mcg / ug)" do
      for unit <- ["µg", "mcg", "ug"] do
        assert {:ok, grams} = Nu.to_grams(900, unit)
        assert_in_delta grams, 0.0009, 1.0e-9
      end
    end

    test "is case- and whitespace-insensitive on the unit" do
      assert {:ok, 1.0} = Nu.to_grams(1000, " MG ")
    end

    test "returns :error for non-mass units" do
      assert :error = Nu.to_grams(200, "kcal")
      assert :error = Nu.to_grams(300, "IU")
    end

    test "returns :error for a missing or non-string unit" do
      assert :error = Nu.to_grams(5, nil)
      assert :error = Nu.to_grams(5, "")
    end

    test "returns :error when amount is not a number" do
      assert :error = Nu.to_grams(nil, "g")
    end
  end

  describe "macronutrient?/1" do
    test "classifies macronutrients (incl. fat subtypes) as true" do
      for label <- [
            "Protein",
            "Carbohydrates",
            "Total Fat",
            "Saturated Fat",
            "Total Sugars",
            "Added Sugars",
            "Fiber"
          ] do
        assert Nu.macronutrient?(label), "expected #{label} to be a macronutrient"
      end
    end

    test "classifies vitamins and minerals as micronutrients (false)" do
      for label <- ["Sodium", "Calcium", "Iron", "Potassium", "Vitamin C", "Cholesterol"] do
        refute Nu.macronutrient?(label), "expected #{label} to be a micronutrient"
      end
    end

    test "is case-insensitive" do
      assert Nu.macronutrient?("total fat")
    end

    test "returns false for non-binary input" do
      refute Nu.macronutrient?(nil)
    end
  end

  describe "consumed_fraction/1" do
    test "scales by consume_portions / servings" do
      assert Nu.consumed_fraction(%{consume_portions: 1, servings: 4}) == 0.25
      assert Nu.consumed_fraction(%{consume_portions: 3, servings: 2}) == 1.5
    end

    test "reads servings from a nested recipe when not hoisted" do
      rum = %{consume_portions: 2, recipe: %{servings: 4}}
      assert Nu.consumed_fraction(rum) == 0.5
    end

    test "falls back to 1.0 when servings or portions are missing or non-positive" do
      assert Nu.consumed_fraction(%{consume_portions: 2}) == 1.0
      assert Nu.consumed_fraction(%{servings: 4}) == 1.0
      assert Nu.consumed_fraction(%{consume_portions: 2, servings: 0}) == 1.0
      assert Nu.consumed_fraction(%{consume_portions: nil, servings: 4}) == 1.0
    end
  end

  describe "scale_nutrient_map/2" do
    test "scales top-level and nested children amounts, leaving other fields intact" do
      nutrients = %{
        "Total Fat" => %{
          "name" => "Total Fat",
          "amount" => 10.0,
          "measurement_unit" => "g",
          "children" => [
            %{"name" => "Saturated Fat", "amount" => 4.0, "measurement_unit" => "g"}
          ]
        }
      }

      scaled = Nu.scale_nutrient_map(nutrients, 0.25)

      fat = scaled["Total Fat"]
      assert fat["amount"] == 2.5
      assert fat["measurement_unit"] == "g"
      assert [%{"amount" => child_amount, "name" => "Saturated Fat"}] = fat["children"]
      assert child_amount == 1.0
    end

    test "leaves entries without a numeric amount untouched" do
      nutrients = %{"Water" => %{"name" => "Water", "measurement_unit" => "g"}}
      assert Nu.scale_nutrient_map(nutrients, 0.5) == nutrients
    end
  end

  describe "summarize_meals_nutrients/1 with portions" do
    test "aggregates recipe nutrients scaled to the consumed portions" do
      meal = %{
        recipe_user_meals: [
          %{
            consume_portions: 1,
            servings: 4,
            recipe_nutrients: %{
              "Protein" => %{"name" => "Protein", "amount" => 40.0, "measurement_unit" => "g"}
            }
          }
        ],
        ingredient_user_meals: []
      }

      summary = Nu.summarize_meals_nutrients([meal])

      assert %{"Protein" => %{"amount" => amount}} = summary
      assert_in_delta amount, 10.0, 1.0e-9
    end
  end
end
