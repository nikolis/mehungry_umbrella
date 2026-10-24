defmodule Mehungry.AI.Eval.MealPlanScorer do
  @moduledoc """
  Layer-1 (deterministic) quality scorer for AI-generated meal plans.

  Takes the normalized plan entries `MealPlanAgent.run/5` returns (see
  `MealPlanAgent.normalize_entry/2`) plus a context map, and returns a structured
  **scorecard** of objective, LLM-free checks. This is the backbone of the
  meal-plan eval harness: cheap, reproducible, and regression-safe.

  It does NOT judge soft/culinary qualities (coherence, "does breakfast read as
  breakfast", variety *feel*) — those are deferred to a Layer-2 LLM-as-judge.

  ## Context keys (all optional)

    * `:avoid_terms`          — downcased substrings no food may contain (hard rule)
    * `:preferred_terms`      — downcased substrings the plan should feature
    * `:recipe_names`         — `%{recipe_id => name}` for name-based checks
    * `:ingredient_names`     — `%{ingredient_id => name}`
    * `:daily_calorie_target` — number; enables the calorie-fit check
    * `:day_macros`           — `%{day_index => %{energy_kcal: n, ...}}`, produced
      by the caller via the app's own `NutrientUtils.summarize_meals_nutrients/1`
      → `macro_summary/1` (parity — never recompute macros here)

  ## Scorecard

      %{
        checks: [%{key:, status: :pass | :warn | :fail | :skip, score: 0.0..1.0, detail:}],
        score: 0.0..1.0,     # mean of non-skipped check scores
        passed?: boolean,    # score >= @pass_threshold and no :fail check
        summary: "..."       # one-line human summary
      }
  """

  alias Mehungry.History.MealType

  @days 7
  @slots_per_day 5
  @expected_entries @days * @slots_per_day
  @max_recipe_repeats 2
  @snack_meal_types ~w(morning_snack afternoon_snack)
  @calorie_tolerance 0.20
  @pass_threshold 0.8

  @doc "Scores `entries` against `context`; see moduledoc for the scorecard shape."
  def score(entries, context \\ %{}) when is_list(entries) do
    checks = [
      check_completeness(entries),
      check_slots_filled(entries),
      check_variety(entries),
      check_snacks_are_ingredients(entries),
      check_avoid_foods(entries, context),
      check_preferred_foods(entries, context),
      check_calorie_fit(context)
    ]

    scored = Enum.reject(checks, &(&1.status == :skip))
    agg = if scored == [], do: 0.0, else: mean(Enum.map(scored, & &1.score))
    passed? = agg >= @pass_threshold and not Enum.any?(checks, &(&1.status == :fail))

    %{
      checks: checks,
      score: Float.round(agg, 3),
      passed?: passed?,
      summary: summarize(checks, agg, passed?)
    }
  end

  @doc "Renders a scorecard as a multi-line string for test logs / mix tasks."
  def format(%{checks: checks, score: score, passed?: passed?}) do
    header = "Meal-plan scorecard — #{pct(score)} (#{if passed?, do: "PASS", else: "FAIL"})"

    lines =
      Enum.map(checks, fn c ->
        "  [#{badge(c.status)}] #{c.key} (#{pct(c.score)}) — #{c.detail}"
      end)

    Enum.join([header | lines], "\n")
  end

  # ── checks ──────────────────────────────────────────────────────────────────

  defp check_completeness([]) do
    check(:completeness, :fail, 0.0, "no entries — the agent never submitted a plan")
  end

  defp check_completeness(entries) do
    n = length(entries)

    status =
      cond do
        n == @expected_entries -> :pass
        n == 0 -> :fail
        true -> :warn
      end

    check(
      :completeness,
      status,
      min(n, @expected_entries) / @expected_entries,
      "#{n}/#{@expected_entries} entries"
    )
  end

  # Every (day_index, meal_type) in the 7×5 grid should be filled exactly once.
  defp check_slots_filled(entries) do
    expected =
      for d <- 1..@days, mt <- MealType.values(), into: MapSet.new(), do: {d, mt}

    counts =
      Enum.frequencies_by(entries, fn e -> {e[:day_index] || e["day_index"], meal_type(e)} end)

    filled_once = Enum.count(expected, fn key -> Map.get(counts, key) == 1 end)
    dupes = Enum.count(counts, fn {_k, c} -> c > 1 end)

    missing = MapSet.size(expected) - Enum.count(expected, &Map.has_key?(counts, &1))
    status = if filled_once == @expected_entries, do: :pass, else: :warn

    check(
      :all_slots_filled,
      status,
      filled_once / @expected_entries,
      "#{filled_once}/#{@expected_entries} slots filled exactly once (#{missing} missing, #{dupes} duplicated)"
    )
  end

  # No recipe should appear more than @max_recipe_repeats across the week.
  defp check_variety(entries) do
    recipe_ids = for e <- entries, id = recipe_id(e), do: id
    total = length(recipe_ids)

    if total == 0 do
      check(:variety, :skip, 0.0, "no recipe entries to evaluate")
    else
      over =
        recipe_ids
        |> Enum.frequencies()
        |> Enum.map(fn {_id, c} -> max(c - @max_recipe_repeats, 0) end)
        |> Enum.sum()

      offenders = Enum.count(Enum.frequencies(recipe_ids), fn {_, c} -> c > @max_recipe_repeats end)
      status = if over == 0, do: :pass, else: :warn

      check(
        :variety,
        status,
        (total - over) / total,
        "#{offenders} recipe(s) used more than #{@max_recipe_repeats}× (#{over} excess placements of #{total})"
      )
    end
  end

  # Snack slots should be a single whole-food ingredient, not a recipe.
  defp check_snacks_are_ingredients(entries) do
    snacks = Enum.filter(entries, &(meal_type(&1) in @snack_meal_types))
    total = length(snacks)

    if total == 0 do
      check(:snacks_are_ingredients, :skip, 0.0, "no snack slots present")
    else
      ingredient_snacks = Enum.count(snacks, &is_integer(ingredient_id(&1)))
      status = if ingredient_snacks == total, do: :pass, else: :warn

      check(
        :snacks_are_ingredients,
        status,
        ingredient_snacks / total,
        "#{ingredient_snacks}/#{total} snack slots are whole-food ingredients"
      )
    end
  end

  # End-to-end avoid-foods: NO entry's resolved food name may contain an avoid
  # term. This is a hard rule — any violation fails the check outright, catching
  # leaks the filter-level unit test can't (e.g. a compound dish name).
  defp check_avoid_foods(entries, context) do
    terms = context[:avoid_terms] || []

    if terms == [] do
      check(:avoid_foods, :skip, 0.0, "no avoid-foods configured")
    else
      violations =
        for e <- entries,
            name = food_name(e, context),
            term <- terms,
            String.contains?(name, term),
            do: {name, term}

      if violations == [] do
        check(:avoid_foods, :pass, 1.0, "none of #{length(entries)} entries contain an avoided food")
      else
        examples = violations |> Enum.take(3) |> Enum.map_join(", ", fn {n, t} -> "#{n}~#{t}" end)

        check(
          :avoid_foods,
          :fail,
          max(1.0 - length(violations) / max(length(entries), 1), 0.0),
          "#{length(violations)} avoid-food violation(s): #{examples}"
        )
      end
    end
  end

  # At least every preferred term should surface somewhere in the week.
  defp check_preferred_foods(entries, context) do
    terms = context[:preferred_terms] || []

    if terms == [] do
      check(:preferred_foods, :skip, 0.0, "no preferred-foods configured")
    else
      names = Enum.map(entries, &food_name(&1, context))
      hit = Enum.count(terms, fn t -> Enum.any?(names, &String.contains?(&1, t)) end)
      status = if hit == length(terms), do: :pass, else: :warn

      check(
        :preferred_foods,
        status,
        hit / length(terms),
        "#{hit}/#{length(terms)} preferred food(s) appear in the plan"
      )
    end
  end

  # Per-day energy within ±@calorie_tolerance of the target. Needs both the
  # target and caller-computed day macros (app-parity aggregation).
  defp check_calorie_fit(context) do
    target = context[:daily_calorie_target]
    day_macros = context[:day_macros]

    cond do
      is_nil(target) or target <= 0 ->
        check(:calorie_fit, :skip, 0.0, "no daily calorie target set")

      is_nil(day_macros) or day_macros == %{} ->
        check(:calorie_fit, :skip, 0.0, "no day macros supplied (nutrition data unavailable)")

      true ->
        days = Map.values(day_macros)

        kcals = Enum.map(days, fn m -> m[:energy_kcal] || 0 end)

        if Enum.all?(kcals, &(&1 == 0)) do
          check(:calorie_fit, :skip, 0.0, "all day energies are 0 — catalog lacks nutrition data")
        else
          within =
            Enum.count(kcals, fn k -> abs(k - target) / target <= @calorie_tolerance end)

          status = if within == length(kcals), do: :pass, else: :warn
          avg = round(mean(kcals))

          check(
            :calorie_fit,
            status,
            within / length(kcals),
            "#{within}/#{length(kcals)} days within ±#{round(@calorie_tolerance * 100)}% of #{target} kcal (avg #{avg})"
          )
        end
    end
  end

  # ── entry accessors (entries may be atom- or string-keyed) ───────────────────

  defp meal_type(e), do: e[:meal_type] || e["meal_type"]
  defp recipe_id(e), do: e[:recipe_id] || e["recipe_id"]
  defp ingredient_id(e), do: e[:ingredient_id] || e["ingredient_id"]

  # The resolved, downcased food name for an entry, via the context name maps.
  defp food_name(e, context) do
    cond do
      id = recipe_id(e) -> name_from(context[:recipe_names], id)
      id = ingredient_id(e) -> name_from(context[:ingredient_names], id)
      true -> ""
    end
  end

  defp name_from(nil, _id), do: ""
  defp name_from(map, id), do: map |> Map.get(id, "") |> to_string() |> String.downcase()

  # ── helpers ───────────────────────────────────────────────────────────────────

  defp check(key, status, score, detail),
    do: %{key: key, status: status, score: score * 1.0, detail: detail}

  defp mean([]), do: 0.0
  defp mean(nums), do: Enum.sum(nums) / length(nums)

  defp pct(f), do: "#{round(f * 100)}%"

  defp badge(:pass), do: "✓"
  defp badge(:warn), do: "~"
  defp badge(:fail), do: "✗"
  defp badge(:skip), do: "–"

  defp summarize(checks, agg, passed?) do
    tally = Enum.frequencies_by(checks, & &1.status)

    "score=#{pct(agg)} passed=#{passed?} " <>
      "(✓#{tally[:pass] || 0} ~#{tally[:warn] || 0} ✗#{tally[:fail] || 0} –#{tally[:skip] || 0})"
  end
end
