defmodule Mehungry.AI.Agents.PlanProvenanceTest do
  use ExUnit.Case, async: true

  alias Mehungry.AI.Agents.{MealPlanAgent, NutritionistAgent}

  # Guards the recipe-id provenance gate the plan agents gained: submit only
  # accepts recipe_ids the search tools actually surfaced this run. A real
  # catalog recipe the model never searched (or a hallucinated id) must be
  # rejected and steered back to search — mirroring RecipeAgent.check_provenance.

  @start_date ~D[2026-08-20]
  @end_date ~D[2026-08-26]

  defp entry(recipe_id, opts \\ []) do
    %{
      "date" => Keyword.get(opts, :date, "2026-08-20"),
      "slot" => Keyword.get(opts, :slot, "Breakfast"),
      "recipe_id" => recipe_id,
      "cooking_portions" => 2
    }
  end

  describe "MealPlanAgent.validate_plan/5" do
    test "accepts a recipe_id that was searched and is in the catalog" do
      offered = MapSet.new([10])
      valid = MapSet.new([10, 11, 12])

      assert MealPlanAgent.validate_plan([entry(10)], offered, valid, @start_date, @end_date) ==
               []
    end

    test "rejects a real catalog recipe the model never surfaced via search" do
      offered = MapSet.new([10])
      # 12 exists in the catalog but was never returned by search_catalog.
      valid = MapSet.new([10, 11, 12])
      [error] = MealPlanAgent.validate_plan([entry(12)], offered, valid, @start_date, @end_date)
      assert error =~ "was not in your search results"
      assert error =~ "12"
    end

    test "rejects a hallucinated id absent from both offered and catalog" do
      [error] =
        MealPlanAgent.validate_plan(
          [entry(9999)],
          MapSet.new([10]),
          MapSet.new([10]),
          @start_date,
          @end_date
        )

      assert error =~ "was not in your search results"
    end

    test "surfaced-but-not-in-catalog falls through to the catalog error" do
      # Defensive: offered should be a subset of the catalog, but if an id is
      # somehow surfaced yet not persisted, the second gate still catches it.
      offered = MapSet.new([10, 77])
      valid = MapSet.new([10])
      [error] = MealPlanAgent.validate_plan([entry(77)], offered, valid, @start_date, @end_date)
      assert error =~ "not in the catalog"
    end
  end

  describe "MealPlanAgent.validate_plan/7 — ingredients + snack slots" do
    defp ingredient_entry(ingredient_id, opts \\ []) do
      %{
        "date" => Keyword.get(opts, :date, "2026-08-20"),
        "slot" => Keyword.get(opts, :slot, "Morning Snack"),
        "ingredient_id" => ingredient_id,
        "quantity" => Keyword.get(opts, :quantity, 1),
        "unit_selection" => Keyword.get(opts, :unit_selection, 5)
      }
    end

    defp validate(entries, opts) do
      MealPlanAgent.validate_plan(
        entries,
        Keyword.get(opts, :offered_recipes, MapSet.new()),
        Keyword.get(opts, :valid_recipes, MapSet.new()),
        Keyword.get(opts, :offered_ingredients, MapSet.new()),
        Keyword.get(opts, :valid_ingredients, MapSet.new()),
        @start_date,
        @end_date
      )
    end

    test "accepts a searched ingredient entry in a snack slot" do
      assert validate([ingredient_entry(42)],
               offered_ingredients: MapSet.new([42]),
               valid_ingredients: MapSet.new([42])
             ) == []
    end

    test "rejects an ingredient_id the model never surfaced via search" do
      [error] =
        validate([ingredient_entry(99)],
          offered_ingredients: MapSet.new([42]),
          valid_ingredients: MapSet.new([42])
        )

      assert error =~ "was not in your search results"
      assert error =~ "99"
    end

    test "rejects an ingredient entry with a non-positive quantity" do
      errors =
        validate([ingredient_entry(42, quantity: 0)],
          offered_ingredients: MapSet.new([42]),
          valid_ingredients: MapSet.new([42])
        )

      assert Enum.any?(errors, &(&1 =~ "positive quantity"))
    end

    test "rejects an entry with both a recipe_id and an ingredient_id" do
      entry = Map.put(ingredient_entry(42), "recipe_id", 10)

      [error] =
        validate([entry],
          offered_recipes: MapSet.new([10]),
          valid_recipes: MapSet.new([10]),
          offered_ingredients: MapSet.new([42]),
          valid_ingredients: MapSet.new([42])
        )

      assert error =~ "exactly one"
    end

    test "accepts the two new snack slots as valid slot values" do
      for slot <- ["Morning Snack", "Afternoon Snack"] do
        assert validate([ingredient_entry(42, slot: slot)],
                 offered_ingredients: MapSet.new([42]),
                 valid_ingredients: MapSet.new([42])
               ) == []
      end
    end
  end

  describe "NutritionistAgent.validate_entries/5" do
    test "accepts a searched, in-catalog recipe_id" do
      offered = MapSet.new([5])
      valid = MapSet.new([5, 6])

      assert NutritionistAgent.validate_entries(
               [entry(5)],
               offered,
               valid,
               @start_date,
               @end_date
             ) == []
    end

    test "rejects a catalog recipe the model never searched" do
      offered = MapSet.new([5])
      valid = MapSet.new([5, 6])

      [error] =
        NutritionistAgent.validate_entries([entry(6)], offered, valid, @start_date, @end_date)

      assert error =~ "was not in your search results"
    end
  end
end
