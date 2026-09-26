defmodule Mehungry.Health.NutrientRecommendation do
  @moduledoc """
  A dietary recommendation linking a health `Condition` to a **nutrient** —
  e.g. *Anti-Inflammatory → encourage → Omega-3*, *Anti-Inflammatory → limit →
  Saturated Fat*.

  The nutrient sibling of `Mehungry.Health.CompoundRecommendation`. Where the
  compound layer resolves condition → compound → `SpeciesCompoundRelationship`
  (facts) → species → ingredients, the nutrient layer resolves condition →
  nutrient → `IngredientNutrient` (the populated, per-100g USDA fact table) →
  ingredients → recipes, thresholding the numeric `amount` for high/low. See
  `Mehungry.Health.NutrientTargets` for the canonical-name → `Nutrient` rows
  resolution.

  A recommendation references a nutrient by its **canonical name string**
  (`nutrient_name`), never a `nutrient_id` FK: the same nutrient name exists
  under several units (`Nutrient` is unique on `[name, measurement_unit_id]`), and
  this matches how blueprints/presets store nutrient tags (`{:array, :string}`).

  Provenance-rich (`source`, `evidence_level`) and append-friendly: the same
  `(condition, nutrient_name, source)` is deduped (an idempotent correction); the
  same pairing from a different source is kept as its own row.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Health.Condition

  @recommendations ~w(avoid limit caution encourage monitor)
  @severities ~w(low moderate high severe)
  # Reuses the labels produced by `Mehungry.Food.EvidenceAggregation`.
  @evidence_levels ~w(strong moderate limited insufficient)
  @sources ~w(manual ai literature guideline)
  # Sources that carry no PubMed study and must therefore supply a structured
  # `source_reference` citation instead (see `validate_has_citation/1`).
  @unsourced_by_study ~w(manual guideline)

  @type t :: %__MODULE__{}

  schema "nutrient_recommendations" do
    field :nutrient_name, :string
    field :recommendation, :string
    field :severity, :string
    field :evidence_level, :string
    field :source, :string
    field :notes, :string
    # Structured citation for non-PubMed advice: %{"label", "url", "doi", "pmid"}.
    field :source_reference, :map

    belongs_to :condition, Condition

    timestamps()
  end

  def changeset(recommendation, attrs) do
    recommendation
    |> cast(attrs, [
      :condition_id,
      :nutrient_name,
      :recommendation,
      :severity,
      :evidence_level,
      :source,
      :notes,
      :source_reference
    ])
    |> update_change(:nutrient_name, &maybe_trim/1)
    |> validate_required([:condition_id, :nutrient_name, :recommendation, :source])
    |> validate_inclusion(:recommendation, @recommendations)
    |> validate_inclusion(:severity, @severities)
    |> validate_inclusion(:evidence_level, @evidence_levels)
    |> validate_inclusion(:source, @sources)
    |> validate_has_citation()
    |> unique_constraint([:condition_id, :nutrient_name, :source])
  end

  defp maybe_trim(nil), do: nil
  defp maybe_trim(name) when is_binary(name), do: String.trim(name)

  # A manual/guideline recommendation carries no PubMed study, so it must supply a
  # structured `source_reference` — every user-facing conclusion cites a real source.
  # Literature/ai sources get their citation from frozen study links, so they're
  # exempt here (mirrors CompoundRecommendation.validate_has_citation/1).
  defp validate_has_citation(changeset) do
    if get_field(changeset, :source) in @unsourced_by_study do
      case get_field(changeset, :source_reference) do
        ref when is_map(ref) and map_size(ref) > 0 -> changeset
        _ -> add_error(changeset, :source_reference, "is required for a manual/guideline source")
      end
    else
      changeset
    end
  end
end
