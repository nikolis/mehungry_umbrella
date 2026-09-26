defmodule Mehungry.Health.NutrientTargets do
  @moduledoc """
  Bridges a `NutrientRecommendation`'s canonical `nutrient_name` to the raw USDA
  `Food.Nutrient` rows that `Food.IngredientNutrient` references, and carries the
  per-100g `threshold` used to classify a food as "high in" that nutrient.

  This resolves the "three spellings" problem: the canonical map in
  `Mehungry.NutrientUtils` and `Food.NutrientNameNormalizer` collapse the many raw
  USDA nutrient names (e.g. `"PUFA 18:3 n-3 c,c,c"`, `"Fiber, total dietary"`) into
  a handful of display labels. We reuse `NutrientNameNormalizer.normalize/1` to map
  every stored `Nutrient.name` to its canonical label, then group the ids under the
  target labels below.

  Thresholds are per-100g and reuse `Food.NutrientInteractions`'s "significant"
  values (10% of FDA daily value) where they exist; the rest are meaningful-content
  cutoffs. `nutrient_ids_for_label/1` is the read seam used by the `Health` nutrient
  resolution queries; it is cached in `:health_cache` since the nutrient registry is
  effectively static after USDA import.
  """

  import Ecto.Query

  alias Mehungry.Repo
  alias Mehungry.Food.Nutrient
  alias Mehungry.Food.NutrientNameNormalizer

  @cache_key_ns __MODULE__
  @cache_ttl :timer.hours(6)

  # target label => %{match: (canonical -> bool), threshold: per-100g float}.
  # `match` runs against `NutrientNameNormalizer.normalize(nutrient.name)`.
  @targets %{
    "Omega-3" => %{contains: "Omega-3", threshold: 0.3},
    "Fiber" => %{names: ["Fiber"], threshold: 3.0},
    "Monounsaturated Fat" => %{names: ["Monounsaturated Fat"], threshold: 5.0},
    "Vitamin C" => %{names: ["Vitamin C"], threshold: 9.0},
    "Vitamin E" => %{names: ["Vitamin E"], threshold: 1.5},
    "Saturated Fat" => %{names: ["Saturated Fat"], threshold: 5.0},
    "Added Sugar" => %{names: ["Added Sugars", "Total Sugars"], threshold: 10.0},
    "Sodium" => %{names: ["Sodium"], threshold: 400.0}
  }

  @doc "The known target labels (for the admin nutrient-recommendation picker)."
  def labels, do: Map.keys(@targets)

  @doc "The per-100g high-content threshold for a target label, or `nil` if unknown."
  def threshold(label), do: get_in(@targets, [label, :threshold])

  @doc """
  The `Food.Nutrient` ids whose canonical label matches `label` (e.g. `"Omega-3"` →
  the ALA/EPA/DHA n-3 rows). Returns `[]` for an unknown label. Cached in
  `:health_cache`.
  """
  def nutrient_ids_for_label(label) do
    case Map.get(@targets, label) do
      nil ->
        []

      spec ->
        key = {@cache_key_ns, {:ids, label}}

        case Cachex.get(:health_cache, key) do
          {:ok, nil} ->
            ids = resolve_ids(spec)
            Cachex.put(:health_cache, key, ids, ttl: @cache_ttl)
            ids

          {:ok, cached} ->
            cached
        end
    end
  end

  @doc """
  Resolves several labels at once to `%{label => {nutrient_ids, threshold}}`,
  dropping labels that resolve to no nutrient rows. Used by the resolution queries.
  """
  def resolve_labels(labels) do
    labels
    |> Enum.uniq()
    |> Enum.reduce(%{}, fn label, acc ->
      case {nutrient_ids_for_label(label), threshold(label)} do
        {[], _} -> acc
        {_ids, nil} -> acc
        {ids, threshold} -> Map.put(acc, label, {ids, threshold})
      end
    end)
  end

  defp resolve_ids(spec) do
    from(n in Nutrient, select: {n.id, n.name})
    |> Repo.all()
    |> Enum.filter(fn {_id, name} -> matches?(spec, NutrientNameNormalizer.normalize(name)) end)
    |> Enum.map(&elem(&1, 0))
    |> Enum.uniq()
  end

  defp matches?(%{contains: needle}, canonical), do: String.contains?(canonical, needle)
  defp matches?(%{names: names}, canonical), do: canonical in names
end
