defmodule Mehungry.Health.CompoundRecommendation do
  @moduledoc """
  A dietary recommendation linking a health `Condition` to a `Compound` —
  e.g. *Kidney Stones → avoid → Oxalate*, *IBS → limit → FODMAP*.

  This is the **advice** layer the "facts only" compound docs
  (`docs/science/food_compounds.md` §4) deliberately defer to: `recommendation` and
  `severity` express guidance, which the `Food.*` fact layers never do. The hard
  rule — a recommendation references a **compound**, never an ingredient — keeps it
  decoupled from ingredient data; the food a patient should avoid is derived by
  composing this with `IngredientCompoundRelationship` at read time.

  Provenance-rich (`source`, `evidence_level`) and append-friendly: the same
  `(condition, compound, source)` is deduped (an idempotent correction), but the
  same pairing from a different source is kept as its own row.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Food.Compound
  alias Mehungry.Health.{Condition, CompoundRecommendationStudy}

  @recommendations ~w(avoid limit caution encourage monitor)
  @severities ~w(low moderate high severe)
  # Reuses the labels produced by `Mehungry.Food.EvidenceAggregation`.
  @evidence_levels ~w(strong moderate limited insufficient)
  @sources ~w(manual ai literature guideline)
  # Sources that carry no PubMed study and must therefore supply a structured
  # `source_reference` citation instead (see `validate_has_citation/1`).
  @unsourced_by_study ~w(manual guideline)

  @type t :: %__MODULE__{}

  schema "compound_recommendations" do
    field :recommendation, :string
    field :severity, :string
    field :evidence_level, :string
    field :source, :string
    field :notes, :string
    # Structured citation for non-PubMed advice: %{"label", "url", "doi", "pmid"}.
    field :source_reference, :map

    belongs_to :condition, Condition
    belongs_to :compound, Compound

    # Frozen PubMed provenance, populated once at promotion (never by re-derivation).
    has_many :recommendation_studies, CompoundRecommendationStudy, foreign_key: :recommendation_id

    has_many :studies, through: [:recommendation_studies, :study]

    timestamps()
  end

  def changeset(recommendation, attrs) do
    recommendation
    |> cast(attrs, [
      :condition_id,
      :compound_id,
      :recommendation,
      :severity,
      :evidence_level,
      :source,
      :notes,
      :source_reference
    ])
    |> validate_required([:condition_id, :compound_id, :recommendation, :source])
    |> validate_inclusion(:recommendation, @recommendations)
    |> validate_inclusion(:severity, @severities)
    |> validate_inclusion(:evidence_level, @evidence_levels)
    |> validate_inclusion(:source, @sources)
    |> validate_has_citation()
    |> unique_constraint([:condition_id, :compound_id, :source])
  end

  # A manual/guideline recommendation carries no PubMed study, so it must supply a
  # structured `source_reference` — every user-facing conclusion cites a real source.
  # Literature/ai sources get their citation from the frozen study links copied at
  # promotion, so they're exempt here.
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
