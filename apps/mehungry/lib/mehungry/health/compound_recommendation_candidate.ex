defmodule Mehungry.Health.CompoundRecommendationCandidate do
  @moduledoc """
  A scored, review-gated condition↔compound recommendation candidate derived from
  literature relations — the ADVISE-layer analogue of `SpeciesCompoundCandidate`.

  It aggregates the `study_entity_relations` between a `Condition` and a `Compound`:
  `relation_counts` tallies the directional valence (negative / positive /
  association), `evidence_score`/`evidence_level` grade the strength, and
  `suggested_recommendation` maps the net valence to a *hint*
  (negative → `encourage`, positive → `avoid`, mixed/association → `neutral`).

  This is a suggestion, never a fact: a candidate is **never auto-promoted** (PubMed
  relation extraction is weak grounds for medical advice). An admin confirms the
  direction and severity, at which point promotion writes a
  `Health.CompoundRecommendation` (`source: "literature"`) and sets
  `promoted_recommendation_id`. `status` moves `pending → promoted | rejected`, and a
  decided status is preserved across re-derivation (only the evidence fields refresh).
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Food.Compound
  alias Mehungry.Health.{CompoundRecommendation, Condition, CompoundRecommendationCandidateStudy}

  # Includes "neutral" (and nil) for Association-only pairs where no direction is
  # implied; the admin must still choose a valid CompoundRecommendation value.
  @suggested ~w(avoid limit caution encourage monitor neutral)
  @statuses ~w(pending promoted rejected)
  @evidence_levels ~w(strong moderate limited insufficient)
  @sources ~w(pubtator manual)

  @type t :: %__MODULE__{}

  schema "compound_recommendation_candidates" do
    field :suggested_recommendation, :string
    field :status, :string, default: "pending"
    field :evidence_score, :float, default: 0.0
    field :evidence_level, :string
    field :relation_counts, :map, default: %{}
    field :study_count, :integer, default: 0
    field :sources, {:array, :string}, default: []
    field :evidence, :map, default: %{}
    field :notes, :string

    belongs_to :condition, Condition
    belongs_to :compound, Compound
    belongs_to :promoted_recommendation, CompoundRecommendation

    has_many :candidate_studies, CompoundRecommendationCandidateStudy, foreign_key: :candidate_id
    has_many :studies, through: [:candidate_studies, :study]

    timestamps()
  end

  def changeset(candidate, attrs) do
    candidate
    |> cast(attrs, [
      :condition_id,
      :compound_id,
      :suggested_recommendation,
      :status,
      :evidence_score,
      :evidence_level,
      :relation_counts,
      :study_count,
      :sources,
      :evidence,
      :notes,
      :promoted_recommendation_id
    ])
    |> validate_required([:condition_id, :compound_id])
    |> validate_inclusion(:status, @statuses)
    |> maybe_validate_inclusion(:suggested_recommendation, @suggested)
    |> maybe_validate_inclusion(:evidence_level, @evidence_levels)
    |> validate_subset(:sources, @sources)
    |> unique_constraint([:condition_id, :compound_id],
      name: :compound_recommendation_candidates_natural_key_index
    )
  end

  defp maybe_validate_inclusion(changeset, field, allowed) do
    case get_field(changeset, field) do
      nil -> changeset
      _ -> validate_inclusion(changeset, field, allowed)
    end
  end
end
