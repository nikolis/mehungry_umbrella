defmodule Mehungry.FoodData.GlycemicIndex.OracleDiff do
  @moduledoc """
  **Internal verification oracle — diff half.** Compares the GI values we *re-derived*
  from primary literature (path B) against the *published* values parsed out of the
  International Tables PDF by `PdfReferenceParser` (see
  `docs/science/glycemic_index_licensing.md`). Pure — takes both datasets as arguments,
  so it's testable without a DB or a PDF; `mix gi.diff` wires the real sources in.

  The compilation is used here **only as a measuring stick** — never a source. For each
  *publishable* oracle row (an unpublished `UO` row is un-re-derivable, so it's counted
  as an expected gap, not a miss) we fuzzy-match the food to one of our species that
  carries a re-derived GI value and bucket the pair:

    * **agree** — a re-derived value is within `:tolerance` GI units of the published one;
    * **diverge** — matched a species, but every re-derived value is off by more than the
      tolerance → the *"divergence to investigate"* bucket (often the published value is a
      multi-study mean vs our single-paper extraction);
    * **uncovered** — no species with a re-derived value matched the food.

  It also surfaces `orphan_species` — species we re-derived a value for that matched no
  publishable oracle row (a novel value, or a name mismatch worth checking).
  """

  alias Mehungry.Food.Ingredient

  @default_tolerance 10.0
  @default_similarity 0.82

  @doc """
  Compare `oracle_rows` (from `PdfReferenceParser`) against `rederived`
  (`[%{name: species_name, values: [gi_value, ...]}]`). Options: `:tolerance`
  (default #{@default_tolerance} GI units) and `:min_similarity` (default
  #{@default_similarity} jaro). Returns a report map with counts, percentages, and the
  divergence + orphan detail lists.
  """
  def compare(oracle_rows, rederived, opts \\ []) do
    tol = Keyword.get(opts, :tolerance, @default_tolerance)
    min_sim = Keyword.get(opts, :min_similarity, @default_similarity)

    species = normalize_rederived(rederived)
    {publishable, unpublished} = Enum.split_with(oracle_rows, &(not &1.unpublished))

    results = Enum.map(publishable, &classify(&1, species, tol, min_sim))

    agree = for r <- results, r.bucket == :agree, do: r
    diverge = for r <- results, r.bucket == :diverge, do: r
    uncovered = for r <- results, r.bucket == :uncovered, do: r

    matched_norms = for r <- results, r.bucket != :uncovered, into: MapSet.new(), do: r.species_norm
    orphans = for s <- species, not MapSet.member?(matched_norms, s.norm), do: s.name

    covered = length(agree) + length(diverge)

    %{
      total_oracle: length(oracle_rows),
      unpublished: length(unpublished),
      publishable: length(publishable),
      covered: covered,
      agree: length(agree),
      diverge: length(diverge),
      uncovered: length(uncovered),
      coverage_pct: pct(covered, length(publishable)),
      agreement_pct: pct(length(agree), covered),
      divergences: Enum.sort_by(diverge, & &1.delta, :desc) |> Enum.map(&present/1),
      orphan_species: Enum.sort(orphans)
    }
  end

  # ── Classification ───────────────────────────────────────────────────────────

  defp classify(row, species, tol, min_sim) do
    head = normalize(head_of(row.food_item))

    case best_match(species, head, min_sim) do
      %{name: name, norm: norm, values: [_ | _] = values} ->
        {closest, delta} = nearest(values, row.gi_value)
        bucket = if delta <= tol, do: :agree, else: :diverge

        %{
          bucket: bucket,
          food: row.food_item,
          oracle_gi: row.gi_value,
          our_gi: closest,
          delta: Float.round(delta, 1),
          species: name,
          species_norm: norm
        }

      _ ->
        %{bucket: :uncovered, food: row.food_item, oracle_gi: row.gi_value}
    end
  end

  defp best_match(_species, "", _min_sim), do: nil

  defp best_match(species, head, min_sim) do
    species
    |> Enum.map(fn s -> {s, jaro(head, s.norm)} end)
    |> Enum.max_by(&elem(&1, 1), fn -> {nil, 0.0} end)
    |> case do
      {s, sim} when sim >= min_sim -> s
      _ -> nil
    end
  end

  defp nearest(values, target) do
    values
    |> Enum.map(fn v -> {v, abs(v - target)} end)
    |> Enum.min_by(&elem(&1, 1))
  end

  # ── Helpers ──────────────────────────────────────────────────────────────────

  defp normalize_rederived(rederived) do
    for %{name: name, values: values} <- rederived do
      %{name: name, norm: normalize(name), values: Enum.filter(values, &is_number/1)}
    end
  end

  # Head of a food item = the segment before the first comma or paren.
  defp head_of(food_item) do
    food_item |> to_string() |> String.split(~r/[,(]/, parts: 2) |> hd() |> String.trim()
  end

  defp normalize(nil), do: ""
  defp normalize(s) when is_binary(s), do: Ingredient.normalize_string(s)

  defp jaro(_a, ""), do: 0.0
  defp jaro("", _b), do: 0.0
  defp jaro(a, b), do: String.jaro_distance(a, b)

  defp present(r), do: Map.take(r, [:food, :species, :oracle_gi, :our_gi, :delta])

  defp pct(_n, 0), do: 0.0
  defp pct(n, total), do: Float.round(n * 100 / total, 1)
end
