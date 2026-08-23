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
      assert MealPlanAgent.validate_plan([entry(10)], offered, valid, @start_date, @end_date) == []
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
      [error] = MealPlanAgent.validate_plan([entry(9999)], MapSet.new([10]), MapSet.new([10]), @start_date, @end_date)
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

  describe "NutritionistAgent.validate_entries/5" do
    test "accepts a searched, in-catalog recipe_id" do
      offered = MapSet.new([5])
      valid = MapSet.new([5, 6])
      assert NutritionistAgent.validate_entries([entry(5)], offered, valid, @start_date, @end_date) == []
    end

    test "rejects a catalog recipe the model never searched" do
      offered = MapSet.new([5])
      valid = MapSet.new([5, 6])
      [error] = NutritionistAgent.validate_entries([entry(6)], offered, valid, @start_date, @end_date)
      assert error =~ "was not in your search results"
    end
  end
end
