defmodule Mehungry.Food.EvidenceAggregation do
  @moduledoc """
  Read-only aggregation over `Mehungry.Food.CompoundMeasurement` rows: given every
  immutable per-study observation for an `(ingredient, compound)` pair, it computes
  an `Mehungry.Food.IngredientCompoundSummary` — descriptive statistics plus a
  transparent evidence score.

      Food.summarize(spinach.id, oxalate.id)
      #=> {:ok, %IngredientCompoundSummary{
      #        mean: 750.0, min: 600.0, max: 900.0, study_count: 14,
      #        evidence_level: :strong, ...}}

  This is the aggregation layer that `docs/compound_measurements.md` §7 defers. It
  **only reads** the measurement rows and never mutates them; no aggregate is
  persisted (the summary is recomputed on demand).

  ## Units are not mixed

  `unit` is free text and heterogeneous units (`mg/100g` vs `g/kg`) cannot be
  averaged without conversion. Rather than fabricate conversions, the summary
  aggregates over the **modal unit** (the most frequently reported one) and reports
  `units_present` and `total_measurement_count`, so a caller can see when other
  units were present and excluded from the numeric summary. Unit normalization is a
  deliberate follow-on (see `docs/evidence_aggregation.md`).

  ## Statistics

  `variance` is the **population** variance `Σ(x − mean)² / n` of the observed
  values (a description of the data we hold, not an inferential estimate); `std_dev`
  is its square root. With fewer than two values the variance is `0.0`.

  ## Evidence score

  The score is a documented, auditable weighted blend of five 0.0–1.0 components,
  each returned on the summary as `evidence_components`:

  | Component | Weight | Basis |
  |---|---|---|
  | `:study_count` | 0.30 | Distinct cataloged studies, saturating at 10. |
  | `:consistency` | 0.25 | Coefficient of variation (tight values ⇒ high). |
  | `:analytical_method` | 0.20 | Lab-technique tier (HPLC/MS high, estimated low). |
  | `:recency` | 0.15 | Age of the newest linked study. |
  | `:publication_quality` | 0.10 | Study-backing and reported sample sizes. |

  `evidence_level` labels the score (`:strong ≥ 0.75`, `:moderate ≥ 0.5`,
  `:limited ≥ 0.25`, else `:insufficient`), with a guardrail: a pair backed by at
  most one study is capped at `:limited` — a single paper can never read as
  "Strong".

  ## Not medical advice

  `evidence_level` measures **how well-supported the numbers are**, not whether a
  food is good or bad to eat. This layer summarizes evidence; it produces no dietary
  recommendation, threshold, or health claim.
  """

  import Ecto.Query, warn: false

  alias Mehungry.Repo
  alias Mehungry.Food.{CompoundMeasurement, IngredientCompoundSummary}

  # Weights for the evidence-score components; must sum to 1.0. Tunable here.
  @component_weights %{
    study_count: 0.30,
    consistency: 0.25,
    analytical_method: 0.20,
    recency: 0.15,
    publication_quality: 0.10
  }

  # Analytical-method rigor tiers → component score.
  @analytical_tier_scores %{high: 1.0, medium: 0.6, low: 0.3, unknown: 0.4}

  # Ordered weakest→strongest, for capping the level of thin evidence.
  @levels [:insufficient, :limited, :moderate, :strong]

  # ── Public API ─────────────────────────────────────────────────────────────

  @doc """
  Summarize every measurement of `compound_id` in `ingredient_id`.

  Returns `{:ok, %IngredientCompoundSummary{}}`, or `{:error, :no_measurements}`
  when the pair has no recorded observations.
  """
  @spec summarize(integer(), integer()) ::
          {:ok, IngredientCompoundSummary.t()} | {:error, :no_measurements}
  def summarize(ingredient_id, compound_id) do
    ingredient_id
    |> measurements_query(compound_id)
    |> Repo.all()
    |> build_summary(ingredient_id, compound_id)
  end

  @doc """
  Summarize every compound measured in `ingredient_id`, one summary per compound
  (ascending `compound_id`). Reads all of the ingredient's measurements in a single
  query. Compounds with no measurements are absent from the result.
  """
  @spec summarize_for_ingredient(integer()) :: [IngredientCompoundSummary.t()]
  def summarize_for_ingredient(ingredient_id) do
    ingredient_id
    |> measurements_query()
    |> Repo.all()
    |> Enum.group_by(& &1.compound_id)
    |> Enum.map(fn {compound_id, measurements} ->
      {:ok, summary} = build_summary(measurements, ingredient_id, compound_id)
      summary
    end)
    |> Enum.sort_by(& &1.compound_id)
  end

  # ── Query (reads the immutable measurement rows; preloads the study) ─────────

  defp measurements_query(ingredient_id, compound_id) do
    from(m in CompoundMeasurement,
      where: m.ingredient_id == ^ingredient_id and m.compound_id == ^compound_id,
      preload: [:study]
    )
  end

  defp measurements_query(ingredient_id) do
    from(m in CompoundMeasurement, where: m.ingredient_id == ^ingredient_id, preload: [:study])
  end

  # ── Summary assembly ─────────────────────────────────────────────────────────

  defp build_summary([], _ingredient_id, _compound_id), do: {:error, :no_measurements}

  defp build_summary(measurements, ingredient_id, compound_id) do
    {unit, summarized} = pick_modal_unit(measurements)
    stats = compute_stats(Enum.map(summarized, & &1.value))
    study_count = distinct_study_count(summarized)
    components = evidence_components(summarized, stats, study_count)
    score = weighted_score(components)

    summary = %IngredientCompoundSummary{
      ingredient_id: ingredient_id,
      compound_id: compound_id,
      unit: unit,
      mean: stats.mean,
      median: stats.median,
      min: stats.min,
      max: stats.max,
      variance: stats.variance,
      std_dev: stats.std_dev,
      study_count: study_count,
      measurement_count: length(summarized),
      total_measurement_count: length(measurements),
      units_present: measurements |> Enum.map(& &1.unit) |> Enum.uniq() |> Enum.sort(),
      evidence_score: score,
      evidence_components: components,
      evidence_level: evidence_level(score, study_count)
    }

    {:ok, summary}
  end

  # The most frequently reported unit wins; ties broken alphabetically for
  # determinism. Only measurements in that unit feed the numeric statistics.
  defp pick_modal_unit(measurements) do
    measurements
    |> Enum.group_by(& &1.unit)
    |> Enum.sort_by(fn {unit, group} -> {-length(group), unit} end)
    |> hd()
  end

  defp distinct_study_count(measurements) do
    measurements
    |> Enum.map(& &1.study_id)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> length()
  end

  # ── Descriptive statistics ───────────────────────────────────────────────────

  defp compute_stats(values) do
    n = length(values)
    sorted = Enum.sort(values)
    mean = Enum.sum(values) / n
    variance = population_variance(values, mean, n)

    %{
      mean: Float.round(mean, 2),
      median: Float.round(median(sorted), 2),
      min: List.first(sorted),
      max: List.last(sorted),
      variance: Float.round(variance, 2),
      std_dev: Float.round(:math.sqrt(variance), 2)
    }
  end

  defp population_variance(_values, _mean, n) when n < 2, do: 0.0

  defp population_variance(values, mean, n) do
    Enum.reduce(values, 0.0, fn v, acc -> acc + :math.pow(v - mean, 2) end) / n
  end

  defp median(sorted) do
    n = length(sorted)
    mid = div(n, 2)

    if rem(n, 2) == 1 do
      Enum.at(sorted, mid) * 1.0
    else
      (Enum.at(sorted, mid - 1) + Enum.at(sorted, mid)) / 2
    end
  end

  # ── Evidence score components (each 0.0–1.0) ─────────────────────────────────

  defp evidence_components(measurements, stats, study_count) do
    %{
      study_count: round3(study_count_score(study_count)),
      consistency: round3(consistency_score(stats.mean, stats.std_dev, length(measurements))),
      analytical_method: round3(analytical_method_score(measurements)),
      recency: round3(recency_score(latest_study_year(measurements))),
      publication_quality: round3(publication_quality_score(measurements))
    }
  end

  # More independent studies ⇒ stronger; saturates once we have ~10.
  defp study_count_score(study_count), do: min(study_count / 10, 1.0)

  # Tighter agreement ⇒ stronger. Uses the coefficient of variation; a single value
  # (or a zero mean, where CV is undefined) is neutral — no consistency evidence.
  defp consistency_score(_mean, _std_dev, count) when count < 2, do: 0.5
  defp consistency_score(mean, _std_dev, _count) when mean == 0.0, do: 0.5

  defp consistency_score(mean, std_dev, _count) do
    cv = std_dev / mean
    clamp(1.0 - cv / 0.5, 0.0, 1.0)
  end

  # Average lab-technique rigor across the measurements.
  defp analytical_method_score(measurements) do
    measurements
    |> Enum.map(&Map.fetch!(@analytical_tier_scores, analytical_tier(&1.analytical_method)))
    |> average()
  end

  defp analytical_tier(nil), do: :unknown

  defp analytical_tier(method) do
    m = String.downcase(method)

    cond do
      contains_any?(m, ["hplc", "uplc", "lc-ms", "lc/ms", "gc-ms", "gc/ms", "mass spec", "chromatograph"]) ->
        :high

      contains_any?(m, ["spectrophotom", "colorimetr", "enzymatic", "titration", "elisa"]) ->
        :medium

      contains_any?(m, ["estimat", "calculat", "nir", "assumed"]) ->
        :low

      true ->
        :unknown
    end
  end

  # Newer evidence ⇒ stronger. Full credit within 2 years, decaying to a floor by 15.
  defp recency_score(nil), do: 0.4

  defp recency_score(year) do
    age = Date.utc_today().year - year

    cond do
      age <= 2 -> 1.0
      age >= 15 -> 0.1
      true -> 1.0 - (age - 2) / 13 * 0.9
    end
  end

  defp latest_study_year(measurements) do
    measurements
    |> Enum.map(& &1.study)
    |> Enum.reject(&(is_nil(&1) or match?(%Ecto.Association.NotLoaded{}, &1)))
    |> Enum.flat_map(&extract_years(&1.publication_date))
    |> case do
      [] -> nil
      years -> Enum.max(years)
    end
  end

  defp extract_years(nil), do: []

  defp extract_years(date_string) do
    ~r/\b(?:19|20)\d{2}\b/
    |> Regex.scan(date_string)
    |> Enum.map(fn [match] -> String.to_integer(match) end)
  end

  # Study-backing (vs. bare manual entry) and reported sample sizes.
  defp publication_quality_score(measurements) do
    backed = Enum.count(measurements, &(&1.study_id != nil)) / length(measurements)
    0.5 * backed + 0.5 * sample_size_signal(measurements)
  end

  defp sample_size_signal(measurements) do
    measurements
    |> Enum.map(& &1.sample_size)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> 0.3
      sizes -> min(average(sizes) / 30, 1.0)
    end
  end

  # ── Score → level ────────────────────────────────────────────────────────────

  defp weighted_score(components) do
    @component_weights
    |> Enum.reduce(0.0, fn {key, weight}, acc -> acc + weight * Map.fetch!(components, key) end)
    |> Float.round(3)
  end

  # One (or zero) study can never be "strong", regardless of the numeric score.
  defp evidence_level(score, study_count) when study_count <= 1 do
    cap(base_level(score), :limited)
  end

  defp evidence_level(score, _study_count), do: base_level(score)

  defp base_level(score) do
    cond do
      score >= 0.75 -> :strong
      score >= 0.5 -> :moderate
      score >= 0.25 -> :limited
      true -> :insufficient
    end
  end

  defp cap(level, ceiling) do
    if level_index(level) <= level_index(ceiling), do: level, else: ceiling
  end

  defp level_index(level), do: Enum.find_index(@levels, &(&1 == level))

  # ── Small numeric helpers ────────────────────────────────────────────────────

  defp average([]), do: 0.0
  defp average(list), do: Enum.sum(list) / length(list)

  defp clamp(value, low, high), do: value |> max(low) |> min(high)

  defp round3(value), do: Float.round(value, 3)

  defp contains_any?(string, substrings), do: Enum.any?(substrings, &String.contains?(string, &1))
end
