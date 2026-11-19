defmodule Mehungry.AI.Agents.PlanProvenanceTest do
  use ExUnit.Case, async: true

  alias Mehungry.AI.Agents.MealPlanCore

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

  describe "MealPlanCore.validate_plan/5" do
    test "accepts a recipe_id that was searched and is in the catalog" do
      offered = MapSet.new([10])
      valid = MapSet.new([10, 11, 12])

      assert MealPlanCore.validate_plan([entry(10)], offered, valid, @start_date, @end_date) ==
               []
    end

    test "rejects a real catalog recipe the model never surfaced via search" do
      offered = MapSet.new([10])
      # 12 exists in the catalog but was never returned by search_catalog.
      valid = MapSet.new([10, 11, 12])
      [error] = MealPlanCore.validate_plan([entry(12)], offered, valid, @start_date, @end_date)
      assert error =~ "was not in your search results"
      assert error =~ "12"
    end

    test "rejects a hallucinated id absent from both offered and catalog" do
      [error] =
        MealPlanCore.validate_plan(
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
      [error] = MealPlanCore.validate_plan([entry(77)], offered, valid, @start_date, @end_date)
      assert error =~ "not in the catalog"
    end
  end

  describe "MealPlanCore.validate_plan/7 — ingredients + snack slots" do
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
      MealPlanCore.validate_plan(
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

  describe "replace-week plans must cover the main meals" do
    defp acc(mode, offered) do
      %{
        start_date: @start_date,
        mode: mode,
        offered: MapSet.new(offered),
        offered_ingredients: MapSet.new(),
        submitted: nil
      }
    end

    defp full_week(recipe_id) do
      for day <- 0..6, slot <- ["Breakfast", "Lunch", "Dinner"] do
        entry(recipe_id, date: Date.to_string(Date.add(@start_date, day)), slot: slot)
      end
    end

    test "a thin plan is sent back in replace mode, naming what is missing" do
      {result, new_acc} =
        MealPlanCore.submit_plan_tool(%{"entries" => [entry(10)]}, acc(:replace_week, [10]))

      refute result.success
      assert [error] = result.errors
      assert error =~ "every day needs Breakfast, Lunch and Dinner"
      assert error =~ "2026-08-20 Lunch"
      assert error =~ "more)"
      assert new_acc.submitted == nil
    end

    test "a plan with all three main meals every day is accepted (snacks optional)" do
      {result, new_acc} =
        MealPlanCore.submit_plan_tool(%{"entries" => full_week(10)}, acc(:replace_week, [10]))

      assert result.success
      assert length(new_acc.submitted.entries) == 21
    end

    test "only days from first_day on are required" do
      entries = Enum.filter(full_week(10), &(&1["date"] >= "2026-08-24"))
      acc = Map.put(acc(:replace_week, [10]), :first_day, ~D[2026-08-24])

      {result, _} = MealPlanCore.submit_plan_tool(%{"entries" => entries}, acc)
      assert result.success
    end

    test "fill-gaps (and a run with no mode) still accepts a partial plan" do
      for mode <- [:fill_gaps, nil] do
        {result, _} = MealPlanCore.submit_plan_tool(%{"entries" => [entry(10)]}, acc(mode, [10]))
        assert result.success
      end
    end
  end

  describe "free-text avoid terms (client intake)" do
    test "non-answers and fragments are dropped, the rest normalized" do
      assert MealPlanCore.free_text_terms(["-", "no", " None ", "N/A", "όχι", "ok", " Oil ", "ham", "oil"]) ==
               ["oil", "ham"]
    end

    test "they match at word starts, not inside other words" do
      results =
        Enum.map(
          ["Boiled eggs", "Olive oil", "Oils, vegetable", "Graham crackers", "Ham sandwich", "Noodles"],
          &%{name: &1}
        )

      kept = MealPlanCore.reject_avoided_words(results, ["oil", "ham"], & &1.name)
      assert Enum.map(kept, & &1.name) == ["Boiled eggs", "Graham crackers", "Noodles"]
    end

    test "word-start matching works for Greek terms too" do
      results = [%{name: "Σαλάτα με φέτα"}, %{name: "Κοτόπουλο"}]
      kept = MealPlanCore.reject_avoided_words(results, ["φέτα"], & &1.name)
      assert Enum.map(kept, & &1.name) == ["Κοτόπουλο"]
    end

    test "guards keep the two kinds apart and never list a term twice" do
      guards =
        MealPlanCore.guards(
          catalog: :public,
          avoid_terms: ["Peanuts"],
          avoid_word_terms: ["no", "oil", "peanuts"]
        )

      assert guards.avoid_terms == ["peanuts"]
      assert guards.avoid_word_terms == ["oil"]
      assert MealPlanCore.enforced_avoid_terms(guards) == ["peanuts", "oil"]
    end
  end

  describe "avoid-foods enforcement" do
    test "avoid_terms downcases, trims, dedups and drops blanks from a blueprint" do
      bp = %Mehungry.MealBlueprints.Blueprint{avoid_foods: [" Onion ", "garlic", "ONION", ""]}
      assert MealPlanCore.avoid_terms(bp) == ["onion", "garlic"]
    end

    test "avoid_terms is empty for a nil blueprint or empty list" do
      assert MealPlanCore.avoid_terms(nil) == []
      assert MealPlanCore.avoid_terms(%Mehungry.MealBlueprints.Blueprint{avoid_foods: []}) == []
    end

    test "reject_avoided drops results whose name contains an avoid term" do
      results = [
        %{id: 1, name: "Red Onion"},
        %{id: 2, name: "Carrot"},
        %{id: 3, name: "Garlic Powder"},
        %{id: 4, name: "Spinach"}
      ]

      kept = MealPlanCore.reject_avoided(results, ["onion", "garlic"], & &1.name)
      assert Enum.map(kept, & &1.id) == [2, 4]
    end

    test "reject_avoided is a no-op with no avoid terms" do
      results = [%{id: 1, name: "Onion"}]
      assert MealPlanCore.reject_avoided(results, [], & &1.name) == results
    end

    test "matched_avoid_terms returns the terms appearing in any name" do
      names = ["Red Onion Salad", "Grilled Chicken"]
      assert MealPlanCore.matched_avoid_terms(names, ["onion", "garlic"]) == ["onion"]
    end

    test "matched_avoid_terms dedups terms matched across names and is case-insensitive" do
      names = ["ONION soup", "caramelized onion"]
      assert MealPlanCore.matched_avoid_terms(names, ["onion"]) == ["onion"]
    end

    test "matched_avoid_terms is empty with no terms or no match" do
      assert MealPlanCore.matched_avoid_terms(["Carrot"], []) == []
      assert MealPlanCore.matched_avoid_terms(["Carrot"], ["onion"]) == []
    end
  end
end
