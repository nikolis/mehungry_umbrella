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

    test "merges the same nutrient across recipes and ingredient meals" do
      meals = [
        %{
          recipe_user_meals: [
            %{
              consume_portions: 2,
              servings: 2,
              recipe_nutrients: %{
                "Protein" => %{"name" => "Protein", "amount" => 10.0, "measurement_unit" => "g"}
              }
            }
          ],
          ingredient_user_meals: [
            %{
              recipe: %{
                nutrients: [
                  %{
                    name: "Protein",
                    amount: 5.0,
                    measurement_unit: %{name: "g"}
                  }
                ]
              }
            }
          ]
        }
      ]

      assert %{"Protein" => %{"amount" => amount}} = Nu.summarize_meals_nutrients(meals)
      assert_in_delta amount, 15.0, 1.0e-9
    end

    test "normalizes divergent source names from different meals into one canonical bucket" do
      meal = %{
        recipe_user_meals: [
          %{
            consume_portions: 1,
            servings: 1,
            recipe_nutrients: %{
              "Total lipid (fat)" => %{
                "name" => "Total lipid (fat)",
                "amount" => 8.0,
                "measurement_unit" => "g"
              }
            }
          },
          %{
            consume_portions: 1,
            servings: 1,
            recipe_nutrients: %{
              "Fat" => %{"name" => "Fat", "amount" => 2.0, "measurement_unit" => "g"}
            }
          }
        ],
        ingredient_user_meals: []
      }

      summary = Nu.summarize_meals_nutrients([meal])
      assert %{"Total Fat" => %{"amount" => amount}} = summary
      assert_in_delta amount, 10.0, 1.0e-9
    end

    test "returns an empty map for empty meals" do
      assert Nu.summarize_meals_nutrients([]) == %{}
    end
  end

  describe "normalize_nutrient_name/1" do
    test "maps known synonyms to their canonical form" do
      assert Nu.normalize_nutrient_name("Total lipid (fat)") == "Total Fat"
      assert Nu.normalize_nutrient_name("carbohydrate (by difference)") == "Carbohydrates"
      assert Nu.normalize_nutrient_name("Energy (Atwater Specific Factors)") == "Energy"
      assert Nu.normalize_nutrient_name("ascorbic acid") == "Vitamin C"
      assert Nu.normalize_nutrient_name("thiamin") == "Vitamin B1 (Thiamin)"
    end

    test "resolves single-letter mineral symbols via fuzzy fallback" do
      assert Nu.normalize_nutrient_name("na") == "Sodium"
      assert Nu.normalize_nutrient_name("fe") == "Iron"
      assert Nu.normalize_nutrient_name("se") == "Selenium"
    end

    test "capitalizes unknown names as a last resort" do
      assert Nu.normalize_nutrient_name("some mystery nutrient") == "Some Mystery Nutrient"
    end

    test "returns Unknown for non-binary input" do
      assert Nu.normalize_nutrient_name(nil) == "Unknown"
      assert Nu.normalize_nutrient_name(123) == "Unknown"
    end
  end

  describe "merge_nutrients_with_normalization/1" do
    test "sums amounts of synonym-named nutrients and merges children" do
      list = [
        %{
          "Total lipid (fat)" => %{
            "name" => "Total lipid (fat)",
            "amount" => 10.0,
            "measurement_unit" => "g",
            "children" => [
              %{"name" => "Saturated Fat", "amount" => 3.0, "measurement_unit" => "g"}
            ]
          }
        },
        %{
          "Fat" => %{
            "name" => "Fat",
            "amount" => 5.0,
            "measurement_unit" => "g",
            "children" => [
              %{"name" => "Saturated Fat", "amount" => 2.0, "measurement_unit" => "g"}
            ]
          }
        }
      ]

      merged = Nu.merge_nutrients_with_normalization(list)

      assert %{"Total Fat" => fat} = merged
      assert fat["amount"] == 15.0
      assert [%{"name" => "Saturated Fat", "amount" => 5.0}] = fat["children"]
    end
  end

  describe "macro_bucket/1" do
    test "classifies clean and messy labels into the five buckets" do
      assert Nu.macro_bucket("Protein") == :protein
      assert Nu.macro_bucket("Total lipid (fat)") == :fat
      assert Nu.macro_bucket("Carbohydrate, By Difference") == :carbs
      assert Nu.macro_bucket("Fiber, Total Dietary") == :fiber
      assert Nu.macro_bucket("Total Sugars") == :sugars
    end

    test "excludes fat/sugar subtypes and added sugars" do
      assert Nu.macro_bucket("Added Sugars") == nil
      assert Nu.macro_bucket("Cholesterol") == nil
    end

    test "returns nil for blank or non-binary input" do
      assert Nu.macro_bucket("") == nil
      assert Nu.macro_bucket(nil) == nil
    end
  end

  describe "macro_totals/1" do
    test "keeps the largest-amount label per bucket" do
      nutrients = %{
        "Carbohydrates" => %{"name" => "Carbohydrates", "amount" => 40.0},
        "Carbohydrate, By Difference" => %{"name" => "Carbohydrate, By Difference", "amount" => 0.0},
        "Protein" => %{"name" => "Protein", "amount" => 12.0}
      }

      totals = Nu.macro_totals(nutrients)

      assert totals[:carbs]["amount"] == 40.0
      assert totals[:protein]["amount"] == 12.0
    end
  end

  describe "sort_nutrients_for_display/1" do
    test "orders by display priority, then alphabetically" do
      map = %{
        "Iron" => %{},
        "Energy" => %{},
        "Protein" => %{},
        "Zebra Nutrient" => %{}
      }

      names = Nu.sort_nutrients_for_display(map) |> Enum.map(fn {name, _} -> name end)
      assert names == ["Energy", "Protein", "Iron", "Zebra Nutrient"]
    end
  end

  describe "macro_buckets/0" do
    test "lists the five headline buckets in display order" do
      assert Nu.macro_buckets() == [:protein, :fat, :carbs, :sugars, :fiber]
    end
  end
end
