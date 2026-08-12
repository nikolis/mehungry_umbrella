defmodule Mehungry.Food.NutrientCalculationTest do
  @moduledoc """
  Coverage for the authoritative recipe-nutrition calculation path
  (`Mehungry.Food.NutrientCalculation`). The pure helpers are tested with
  hand-built structs (no DB); `validate_ingredient_units/1` is exercised against
  the database via `DataCase`.

  See `docs/nutrition_calculation.md`.
  """
  use Mehungry.DataCase, async: false

  alias Mehungry.Food.NutrientCalculation, as: NC
  alias Mehungry.Food.{Ingredient, IngredientNutrient, IngredientPortion, MeasurementUnit, Nutrient}
  alias Mehungry.FoodFixtures

  # ── struct builders ───────────────────────────────────────────────────────

  defp nutrient(name, unit, opts) do
    %Nutrient{
      name: name,
      number: opts[:number],
      measurement_unit: %MeasurementUnit{name: unit}
    }
  end

  defp ing_nutrient(name, amount, unit, opts \\ []) do
    %IngredientNutrient{
      amount: amount,
      nutrient_id: opts[:nutrient_id] || System.unique_integer([:positive]),
      nutrient: nutrient(name, unit, opts)
    }
  end

  defp portion(id, mu_id, gram_weight, amount) do
    %IngredientPortion{
      id: id,
      measurement_unit_id: mu_id,
      gram_weight: gram_weight,
      amount: amount
    }
  end

  # ════════════════════════════════════════════════════════════════════════
  # calculate_gram_weight/5
  # ════════════════════════════════════════════════════════════════════════

  describe "calculate_gram_weight/5" do
    test "gram-family unit passes quantity straight through as grams" do
      ing = %Ingredient{id: 1, ingredient_portions: []}
      gram_ids = MapSet.new([7])

      assert NC.calculate_gram_weight(ing, 7, nil, 250, gram_ids) == 250.0
    end

    test "resolves via the recipe ingredient's own ingredient_portion_id first" do
      # Two portions for the same unit; the explicit id must win.
      p_by_unit = portion(10, 3, 100.0, 1.0)
      p_explicit = portion(20, 3, 240.0, 1.0)
      ing = %Ingredient{id: 1, ingredient_portions: [p_by_unit, p_explicit]}

      assert NC.calculate_gram_weight(ing, 3, 20, 2, MapSet.new()) == 480.0
    end

    test "falls back to the portion matching measurement_unit_id" do
      p = portion(10, 3, 150.0, 1.0)
      ing = %Ingredient{id: 1, ingredient_portions: [p]}

      assert NC.calculate_gram_weight(ing, 3, nil, 2, MapSet.new()) == 300.0
    end

    test "divides gram_weight by the USDA serving denominator (amount)" do
      # half-cup = 120 g  ->  1 cup = 240 g  ->  2 cups = 480 g
      p = portion(10, 3, 120.0, 0.5)
      ing = %Ingredient{id: 1, ingredient_portions: [p]}

      assert NC.calculate_gram_weight(ing, 3, nil, 2, MapSet.new()) == 480.0
    end

    test "treats a nil amount as 1.0" do
      p = portion(10, 3, 90.0, nil)
      ing = %Ingredient{id: 1, ingredient_portions: [p]}

      assert NC.calculate_gram_weight(ing, 3, nil, 3, MapSet.new()) == 270.0
    end

    test "accepts a string quantity" do
      p = portion(10, 3, 50.0, 1.0)
      ing = %Ingredient{id: 1, ingredient_portions: [p]}

      assert NC.calculate_gram_weight(ing, 3, nil, "4", MapSet.new()) == 200.0
    end

    test "contributes 0 g and warns when no portion resolves for a non-gram unit" do
      ing = %Ingredient{id: 99, ingredient_portions: []}

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert NC.calculate_gram_weight(ing, 3, nil, 5, MapSet.new()) == 0.0
        end)

      assert log =~ "no portion found for ingredient 99"
    end
  end

  # ════════════════════════════════════════════════════════════════════════
  # build_nutrient_list/2  &  filter_energy_duplicates/1
  # ════════════════════════════════════════════════════════════════════════

  describe "build_nutrient_list/2" do
    test "scales each nutrient by gram_weight / 100" do
      ing = %Ingredient{
        ingredient_nutrients: [
          ing_nutrient("Protein", 25.0, "g", number: "203"),
          ing_nutrient("Sodium", 400.0, "mg", number: "307")
        ]
      }

      [protein, sodium] =
        NC.build_nutrient_list(ing, 200.0)
        |> Enum.sort_by(& &1.name)
        |> then(fn list -> [Enum.find(list, &(&1.name == "Protein")), Enum.find(list, &(&1.name == "Sodium"))] end)

      assert protein.amount == 50.0
      assert protein.measurement_unit == "g"
      assert protein.nutrient_number == "203"
      assert sodium.amount == 800.0
      assert sodium.measurement_unit == "mg"
    end

    test "yields an empty list for an ingredient with no nutrients" do
      assert NC.build_nutrient_list(%Ingredient{ingredient_nutrients: []}, 100.0) == []
    end

    test "falls back to the \"g\" unit when a nutrient has no measurement_unit" do
      ing = %Ingredient{
        ingredient_nutrients: [
          %IngredientNutrient{amount: 5.0, nutrient_id: 1, nutrient: %Nutrient{name: "Fiber"}}
        ]
      }

      [n] = NC.build_nutrient_list(ing, 100.0)
      assert n.name == "Fiber"
      assert n.measurement_unit == "g"
    end
  end

  describe "filter_energy_duplicates/1" do
    test "prefers Atwater Specific over all other energy entries" do
      nutrients = [
        ing_nutrient("Energy (Atwater General Factors)", 210.0, "kcal"),
        ing_nutrient("Energy (Atwater Specific Factors)", 200.0, "kcal"),
        ing_nutrient("Energy", 205.0, "kilocalorie"),
        ing_nutrient("Energy", 860.0, "kilojoule"),
        ing_nutrient("Protein", 25.0, "g")
      ]

      result = NC.filter_energy_duplicates(nutrients)
      energy = Enum.filter(result, &String.starts_with?(&1.nutrient.name, "Energy"))

      assert length(energy) == 1
      assert hd(energy).nutrient.name == "Energy (Atwater Specific Factors)"
      # Non-energy nutrients are always preserved.
      assert Enum.any?(result, &(&1.nutrient.name == "Protein"))
    end

    test "falls back to Atwater General when Specific is absent" do
      nutrients = [
        ing_nutrient("Energy (Atwater General Factors)", 210.0, "kcal"),
        ing_nutrient("Energy", 205.0, "kilocalorie")
      ]

      [energy] = NC.filter_energy_duplicates(nutrients)
      assert energy.nutrient.name == "Energy (Atwater General Factors)"
    end

    test "falls back to a plain kcal Energy entry when no Atwater factors exist" do
      nutrients = [
        ing_nutrient("Energy", 860.0, "kilojoule"),
        ing_nutrient("Energy", 205.0, "kilocalorie")
      ]

      [energy] = NC.filter_energy_duplicates(nutrients)
      assert match?(%{name: "kilocalorie"}, energy.nutrient.measurement_unit)
    end

    test "leaves a list with no energy entries untouched" do
      nutrients = [ing_nutrient("Protein", 25.0, "g"), ing_nutrient("Iron", 2.0, "mg")]
      assert NC.filter_energy_duplicates(nutrients) == nutrients
    end
  end

  # ════════════════════════════════════════════════════════════════════════
  # calculate_nutrition_for_recipe/1  &  aggregation helpers
  # ════════════════════════════════════════════════════════════════════════

  describe "calculate_nutrition_for_recipe/1" do
    test "sums nutrients across ingredients and reports totals" do
      ingredients = [
        %{nutrients: [%{name: "Protein", amount: 10.0, measurement_unit: "g", nutrient_id: 1}]},
        %{
          nutrients: [
            %{name: "Protein", amount: 5.0, measurement_unit: "g", nutrient_id: 1},
            %{name: "Energy", amount: 250.0, measurement_unit: "kcal", nutrient_id: 2}
          ]
        }
      ]

      result = NC.calculate_nutrition_for_recipe(ingredients)

      assert result.ingredient_count == 2
      assert result.total_calories == 250.0

      protein = Enum.find(result.flat_nutrients, &(&1.name == "Protein"))
      assert protein.amount == 15.0
    end

    test "produces a priority-sorted structured list (Energy first)" do
      ingredients = [
        %{
          nutrients: [
            %{name: "Protein", amount: 10.0, measurement_unit: "g", nutrient_id: 1},
            %{name: "Energy", amount: 100.0, measurement_unit: "kcal", nutrient_id: 2}
          ]
        }
      ]

      result = NC.calculate_nutrition_for_recipe(ingredients)
      names = Enum.map(result.structured_nutrients, & &1.name)

      assert "Energy" in names
      assert Enum.find_index(names, &(&1 == "Energy")) <
               Enum.find_index(names, &(&1 == "Protein"))
    end
  end

  describe "calculate_total_calories/1" do
    test "returns the Energy amount rounded to a whole number" do
      assert NC.calculate_total_calories([%{name: "Energy", amount: 249.6}]) == 250.0
    end

    test "returns 0 when no Energy entry is present" do
      assert NC.calculate_total_calories([%{name: "Protein", amount: 10.0}]) == 0
    end
  end

  describe "sort_nutrients_by_priority/1" do
    test "orders by the display priority map and drops nil entries" do
      map = %{
        minerals: %{name: "Minerals"},
        Energy: %{name: "Energy"},
        Protein: %{name: "Protein"},
        dropped: nil
      }

      names = NC.sort_nutrients_by_priority(map) |> Enum.map(& &1.name)
      assert names == ["Energy", "Protein", "Minerals"]
    end
  end

  # ════════════════════════════════════════════════════════════════════════
  # numeric coercion helpers
  # ════════════════════════════════════════════════════════════════════════

  describe "safe_to_float/1" do
    test "coerces floats, ints, numeric strings; defaults to 0.0" do
      assert NC.safe_to_float(3.5) == 3.5
      assert NC.safe_to_float(4) == 4.0
      assert NC.safe_to_float("2.5") == 2.5
      assert NC.safe_to_float("nope") == 0.0
      assert NC.safe_to_float(nil) == 0.0
    end
  end

  describe "safe_nutrient_amount/1" do
    test "coerces numbers and defaults non-numeric to 0.0" do
      assert NC.safe_nutrient_amount(1.2) == 1.2
      assert NC.safe_nutrient_amount(3) == 3.0
      assert NC.safe_nutrient_amount(nil) == 0.0
    end
  end

  describe "get_value/2" do
    test "reads a key whether stored as an atom or string" do
      assert NC.get_value(%{name: "x"}, :name) == "x"
      assert NC.get_value(%{"name" => "y"}, :name) == "y"
    end
  end

  # ════════════════════════════════════════════════════════════════════════
  # calculate_recipe_nutrition_value/1 (top-level guard clauses)
  # ════════════════════════════════════════════════════════════════════════

  describe "calculate_recipe_nutrition_value/1" do
    test "returns {0, []} for a recipe with no ingredients" do
      assert NC.calculate_recipe_nutrition_value(%{recipe_ingredients: []}) == {0, []}
      assert NC.calculate_recipe_nutrition_value(%{recipe_ingredients: nil}) == {0, []}
    end
  end

  # ════════════════════════════════════════════════════════════════════════
  # validate_ingredient_units/1  (DB-backed)
  # ════════════════════════════════════════════════════════════════════════

  describe "validate_ingredient_units/1" do
    test "accepts gram-family units without needing a portion" do
      gram = FoodFixtures.measurement_unit_fixture(%{name: "g"})
      ingredient = FoodFixtures.ingredient_fixture()

      params = [%{ingredient_id: ingredient.id, measurement_unit_id: gram.id}]
      assert NC.validate_ingredient_units(params) == :ok
    end

    test "reports ingredient/unit pairs that lack an IngredientPortion" do
      cup = FoodFixtures.measurement_unit_fixture(%{name: "cup"})
      ingredient = FoodFixtures.ingredient_fixture(%{name: "Portionless Ingredient"})

      params = [%{ingredient_id: ingredient.id, measurement_unit_id: cup.id}]

      assert {:error, [%{ingredient_name: name, unit_name: "cup"}]} =
               NC.validate_ingredient_units(params)

      assert name == "Portionless Ingredient"
    end

    test "accepts a non-gram unit once a matching portion exists" do
      cup = FoodFixtures.measurement_unit_fixture(%{name: "cup"})
      ingredient = FoodFixtures.ingredient_fixture()

      Repo.insert!(%IngredientPortion{
        ingredient_id: ingredient.id,
        measurement_unit_id: cup.id,
        gram_weight: 240.0,
        amount: 1.0
      })

      params = [%{ingredient_id: ingredient.id, measurement_unit_id: cup.id}]
      assert NC.validate_ingredient_units(params) == :ok
    end
  end
end
