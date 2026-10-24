defmodule Mehungry.AI.Eval.DietPatternsMechanismTest do
  @moduledoc """
  Deterministic, **token-free** coverage of how all 21 pre-configured diet
  patterns (`Mehungry.MealBlueprints.DietPatterns`) are handled by the mechanism
  the meal-plan agent actually uses — **without** running the LLM.

  Whether a diet is honored is decided by two deterministic levers, not by the
  model:

    1. **The avoid-foods filter** (`MealPlanAgent.reject_avoided/3`) — removes
       catalog candidates whose name contains an avoid term *before* the model
       ever sees them.
    2. **The brief** (`MealBlueprints.blueprint_preferences/1`) — the free-text
       instructions the prompt carries (preferred/avoid foods, nutrient tags).

  This file tests both for every diet against the real seeded catalog. The actual
  agent is exercised **once per full-feature evaluation** in
  `meal_plan_quality_eval_test.exs` (the Low-FODMAP scenario) — we do not re-run
  the LLM 21× to re-check a deterministic filter.

  It also pins the **known limitation**: avoid-foods is literal substring, so
  category-level diets (Vegan → "meat") don't exclude specific foods ("chicken").
  The proper fix is category filtering (`Food.DietClassifier` /
  `Categories.diet_category_ids/1`), tracked by the explicit regression test below.
  """
  use Mehungry.DataCase, async: false

  alias Mehungry.AI.Agents.MealPlanAgent
  alias Mehungry.AI.Eval.MealPlanCatalog
  alias Mehungry.MealBlueprints
  alias Mehungry.MealBlueprints.{Blueprint, DietPatterns}

  setup do
    {:ok, catalog: MealPlanCatalog.seed()}
  end

  describe "avoid-foods filter (reject_avoided/3) — the agent's real gate" do
    test "for every diet, no surviving catalog item contains an avoid term", %{catalog: cat} do
      for d <- DietPatterns.all() do
        terms = MealPlanAgent.avoid_terms(blueprint_from(d))

        survivors =
          names(cat.recipes, & &1.title) ++ names(cat.ingredients, & &1.name)
          |> MealPlanAgent.reject_avoided(terms, & &1)

        leaked =
          for name <- survivors, term <- terms, String.contains?(String.downcase(name), term) do
            {name, term}
          end

        assert leaked == [], "#{d.name}: avoid filter leaked #{inspect(leaked)}"
      end
    end

    test "Low-FODMAP drops the garlic recipe but keeps a clean breakfast", %{catalog: cat} do
      terms = MealPlanAgent.avoid_terms(blueprint_from(DietPatterns.get(:low_fodmap)))

      kept = cat.recipes |> MealPlanAgent.reject_avoided(terms, & &1.title) |> Enum.map(& &1.title)

      refute "Slow Roasted Garlic Chicken Dinner" in kept
      assert "Light Oatmeal Breakfast with Berries" in kept
    end

    test "every diet leaves at least one snack ingredient to build from", %{catalog: cat} do
      for d <- DietPatterns.all() do
        terms = MealPlanAgent.avoid_terms(blueprint_from(d))
        kept = MealPlanAgent.reject_avoided(cat.ingredients, terms, & &1.name)

        assert kept != [], "#{d.name}: avoid filter left no usable ingredients"
      end
    end
  end

  describe "the brief (blueprint_preferences/1) — what the prompt is told" do
    test "every diet produces a non-empty brief naming the diet", %{catalog: _cat} do
      for d <- DietPatterns.all() do
        brief = MealBlueprints.blueprint_preferences(blueprint_from(d))
        assert is_binary(brief) and brief != ""
        assert String.contains?(brief, d.name), "#{d.name}: brief omits the diet name"
      end
    end

    test "avoidance diets carry their avoid-foods into the brief" do
      for d <- DietPatterns.all(), d.avoid_foods != [] do
        brief = MealBlueprints.blueprint_preferences(blueprint_from(d))
        assert String.contains?(brief, "Avoid foods"), "#{d.name}: brief omits avoid foods"

        first = hd(d.avoid_foods)
        assert String.contains?(brief, first), "#{d.name}: brief omits avoid food #{inspect(first)}"
      end
    end
  end

  describe "two complementary layers: substring (specific foods) + category (diets)" do
    # The substring filter is deliberately literal — it's the *specific-food*
    # layer (onion, garlic, honey). It does NOT catch category terms: Vegan's
    # "meat" isn't a substring of "chicken". That gap is closed by the separate
    # *category* layer (`Food.recipe_ids_with_diet_tag/2` /
    # `DietClassifier`), which the agent's `search_catalog` now also applies —
    # proven in `meal_plan_diet_filter_test.exs`. This test pins the division of
    # labour: don't expect the substring layer to do the category layer's job.
    test "the substring layer alone leaves a chicken recipe under Vegan's 'meat'", %{catalog: cat} do
      terms = MealPlanAgent.avoid_terms(blueprint_from(DietPatterns.get(:vegan)))
      kept = cat.recipes |> MealPlanAgent.reject_avoided(terms, & &1.title) |> Enum.map(& &1.title)

      assert "Grilled Chicken Caesar Lunch Wrap" in kept,
             "substring is the specific-food layer; category exclusion is the agent's diet layer"
    end
  end

  @tag :report
  test "per-diet survivor coverage report", %{catalog: cat} do
    rows =
      for d <- DietPatterns.all() do
        terms = MealPlanAgent.avoid_terms(blueprint_from(d))
        r = length(MealPlanAgent.reject_avoided(cat.recipes, terms, & &1.title))
        i = length(MealPlanAgent.reject_avoided(cat.ingredients, terms, & &1.name))

        :io_lib.format("  ~-32ts recipes=~2w/~2w  ingredients=~2w/~2w  avoid_terms=~2w", [
          d.name,
          r,
          length(cat.recipes),
          i,
          length(cat.ingredients),
          length(terms)
        ])
        |> IO.iodata_to_binary()
      end

    IO.puts("\n[diets] catalog survivors after each diet's avoid filter\n" <> Enum.join(rows, "\n"))
  end

  defp blueprint_from(d) do
    %Blueprint{
      name: d.name,
      description: d.description,
      required_nutrients: d.required_nutrients,
      avoid_nutrients: d.avoid_nutrients,
      required_compounds: d.required_compounds,
      avoid_compounds: d.avoid_compounds,
      preferred_foods: d.preferred_foods,
      avoid_foods: d.avoid_foods,
      condition_id: nil
    }
  end

  defp names(items, fun), do: Enum.map(items, fun)
end
