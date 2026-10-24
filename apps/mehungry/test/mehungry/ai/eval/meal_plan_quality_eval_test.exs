defmodule Mehungry.AI.Eval.MealPlanQualityEvalTest do
  @moduledoc """
  Live meal-plan quality eval — runs the REAL `MealPlanAgent` against a seeded
  fixture catalog and scores its output with `MealPlanScorer`.

  Excluded from the normal suite (`@moduletag :ai_eval`) because it calls the
  Anthropic API (costs tokens, needs `ANTHROPIC_API_KEY`). Run on demand:

      mix test --only ai_eval
      EVAL_RUNS=3 mix test --only ai_eval   # N runs per scenario → pass rate

  Each scenario logs a full scorecard plus **catalog coverage** (how many recipes
  the agent actually surfaced). Coverage separates the two failure modes a tester
  otherwise can't tell apart: a bad plan because the agent chose poorly (prompt/
  model) vs. because the catalog was too thin (data).
  """
  use Mehungry.DataCase, async: false

  @moduletag :ai_eval
  # The agent makes several sequential API round-trips.
  @moduletag timeout: 300_000

  require Logger
  alias Mehungry.{History, NutrientUtils}
  alias Mehungry.AI.Agents.MealPlanAgent
  alias Mehungry.AI.MealPlanGenerator
  alias Mehungry.AI.Eval.{MealPlanCatalog, MealPlanScorer, TokenMeter}
  alias Mehungry.MealBlueprints

  @runs String.to_integer(System.get_env("EVAL_RUNS", "1"))

  setup do
    unless System.get_env("ANTHROPIC_API_KEY") do
      raise "ai_eval requires ANTHROPIC_API_KEY — these tests call the live Anthropic API"
    end

    meter = TokenMeter.start()

    on_exit(fn ->
      totals = TokenMeter.stop(meter)
      IO.puts("\n[eval] " <> TokenMeter.format(totals))
    end)

    {:ok, catalog: MealPlanCatalog.seed()}
  end

  test "balanced week — plans meet structural + variety invariants", %{catalog: cat} do
    bp = cat.blueprint_plain
    preferences = MealBlueprints.blueprint_preferences(bp)

    cards =
      run_scenario("balanced-week", cat, preferences, bp, context_overrides(cat, bp))

    # Hard structural invariants hold across every run (not just on average).
    for card <- cards do
      assert check(card, :completeness).status in [:pass, :warn]
      assert check(card, :avoid_foods).status != :fail
    end

    assert_pass_rate(cards, 0.6)
  end

  test "low-FODMAP — never leaks onion or garlic", %{catalog: cat} do
    bp = cat.blueprint_low_fodmap
    preferences = MealBlueprints.blueprint_preferences(bp)

    cards = run_scenario("low-fodmap", cat, preferences, bp, context_overrides(cat, bp))

    # Avoid-foods is a hard rule — a single leak across any run is a failure.
    for card <- cards do
      assert check(card, :avoid_foods).status != :fail,
             "avoid-foods leak: #{check(card, :avoid_foods).detail}"
    end
  end

  # ── scenario runner ───────────────────────────────────────────────────────────

  defp run_scenario(name, cat, preferences, blueprint, context) do
    Enum.map(1..@runs, fn i ->
      case MealPlanAgent.run(preferences, [], cat.start_date, cat.user_id, blueprint) do
        {:ok, entries} ->
          # Materialize onto the calendar and aggregate per-day macros through the
          # app's own path (parity), so `calorie_fit` scores against real numbers.
          context = Map.put(context, :day_macros, day_macros(entries, cat))
          card = MealPlanScorer.score(entries, context)
          log_run(name, i, entries, card, context)
          card

        {:error, reason} ->
          Logger.error("[eval:#{name}] run #{i}/#{@runs} agent error: #{inspect(reason)}")
          MealPlanScorer.score([], context)
      end
    end)
  end

  # Per-day `%{energy_kcal, ...}` map, computed exactly as the calendar does:
  # persist entries → load the week's meals → `summarize_meals_nutrients` →
  # `macro_summary`. Reusing the shared functions keeps the eval from drifting
  # from what the product shows.
  defp day_macros(entries, cat) do
    {:ok, _created, _skipped} =
      MealPlanGenerator.persist_entries_to_calendar(entries, cat.user_id, cat.start_date)

    end_date = Date.add(cat.start_date, 6)

    cat.user_id
    |> History.list_calendar_user_meals(cat.start_date, end_date)
    |> History.format_user_meals()
    |> Enum.group_by(fn m -> Date.diff(NaiveDateTime.to_date(m.start_dt), cat.start_date) + 1 end)
    |> Map.new(fn {day, meals} ->
      {day, meals |> NutrientUtils.summarize_meals_nutrients() |> NutrientUtils.macro_summary()}
    end)
  end

  # Build the scorer context from the catalog + blueprint.
  defp context_overrides(cat, blueprint) do
    %{
      avoid_terms: MealPlanAgent.avoid_terms(blueprint),
      preferred_terms: downcase_list(blueprint.preferred_foods),
      recipe_names: cat.recipe_names,
      ingredient_names: cat.ingredient_names,
      daily_calorie_target: cat.daily_calorie_target
      # :day_macros is added per-run in run_scenario, after the plan is generated.
    }
  end

  defp downcase_list(nil), do: []
  defp downcase_list(list), do: Enum.map(list, &String.downcase/1)

  defp check(card, key), do: Enum.find(card.checks, &(&1.key == key))

  defp assert_pass_rate(cards, min_rate) do
    passed = Enum.count(cards, & &1.passed?)
    rate = passed / length(cards)

    assert rate >= min_rate,
           "pass rate #{Float.round(rate, 2)} below #{min_rate} (#{passed}/#{length(cards)} runs)"
  end

  defp log_run(name, i, entries, card, context) do
    coverage = coverage_line(entries, context)

    IO.puts("""

    [eval:#{name}] run #{i}/#{@runs}
    #{MealPlanScorer.format(card)}
    #{coverage}
    """)
  end

  # Catalog coverage: distinct recipes/ingredients the plan actually used out of
  # what was seeded — the signal that tells "thin catalog" apart from "bad agent".
  defp coverage_line(entries, context) do
    used_recipes = entries |> Enum.map(&(&1[:recipe_id] || &1["recipe_id"])) |> drop_nil_uniq()
    used_ings = entries |> Enum.map(&(&1[:ingredient_id] || &1["ingredient_id"])) |> drop_nil_uniq()

    "  coverage: #{length(used_recipes)}/#{map_size(context.recipe_names)} recipes, " <>
      "#{length(used_ings)}/#{map_size(context.ingredient_names)} ingredients used"
  end

  defp drop_nil_uniq(list), do: list |> Enum.reject(&is_nil/1) |> Enum.uniq()
end
