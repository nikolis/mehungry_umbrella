defmodule Mehungry.Health.ConditionRecommendationCandidate do
  @moduledoc """
  A phase-aware, review-gated recommendation candidate extracted from a condition's
  literature by the offline Python service — the state-aware sibling of
  `CompoundRecommendationCandidate`.

  Where `CompoundRecommendationCandidate` is derived from state-blind PubTator
  relations, this candidate is extracted from study **prose** and is therefore tagged
  with a `condition_state` (nullable = general / all-phase). Its target may be a
  registry `Compound`, a nutrient (by canonical `nutrient_name`), or a free-text
  `food_pattern` (e.g. *"low-residue"*) — whatever the extractor grounded; unresolved
  terms keep just `raw_term` for the admin.

  Never auto-promoted: an admin confirms direction + severity + state at
  `/professional/health`, at which point promotion writes a
  `ConditionStateRecommendation` and sets `promoted_recommendation_id`. A decided
  `status` is preserved across re-extraction (only evidence fields refresh).

  Idempotency is via the app-computed `dedup_key` (the natural key spans nullable
  columns, so a single deterministic string is used instead of a composite index).
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Food.Compound

  alias Mehungry.Health.{
    Condition,
    ConditionState,
    ConditionStateRecommendation,
    ConditionRecommendationCandidateStudy
  }

  @target_kinds ~w(compound nutrient food_pattern)
  @suggested ~w(avoid limit caution encourage monitor neutral)
  @severities ~w(low moderate high severe)
  @statuses ~w(pending promoted rejected)
  @evidence_levels ~w(strong moderate limited insufficient)

  @type t :: %__MODULE__{}

  schema "condition_recommendation_candidates" do
    field :nutrient_name, :string
    field :raw_term, :string
    field :target_kind, :string
    field :suggested_recommendation, :string
    field :suggested_severity, :string
    field :status, :string, default: "pending"
    field :evidence_score, :float, default: 0.0
    field :confidence, :float
    field :evidence_level, :string
    field :study_count, :integer, default: 0
    field :evidence, :map, default: %{}
    field :extraction_method, :string, default: "llm_fulltext"
    field :notes, :string
    field :dedup_key, :string

    belongs_to :condition, Condition
    belongs_to :condition_state, ConditionState
    belongs_to :compound, Compound
    belongs_to :promoted_recommendation, ConditionStateRecommendation

    has_many :candidate_studies, ConditionRecommendationCandidateStudy,
      foreign_key: :candidate_id

    has_many :studies, through: [:candidate_studies, :study]

    timestamps()
  end

  def changeset(candidate, attrs) do
    candidate
    |> cast(attrs, [
      :condition_id,
      :condition_state_id,
      :compound_id,
      :nutrient_name,
      :raw_term,
      :target_kind,
      :suggested_recommendation,
      :suggested_severity,
      :status,
      :evidence_score,
      :confidence,
      :evidence_level,
      :study_count,
      :evidence,
      :extraction_method,
      :notes,
      :dedup_key,
      :promoted_recommendation_id
    ])
    |> validate_required([:condition_id, :raw_term, :target_kind, :dedup_key])
    |> validate_inclusion(:target_kind, @target_kinds)
    |> validate_inclusion(:status, @statuses)
    |> maybe_validate_inclusion(:suggested_recommendation, @suggested)
    |> maybe_validate_inclusion(:suggested_severity, @severities)
    |> maybe_validate_inclusion(:evidence_level, @evidence_levels)
    |> unique_constraint(:dedup_key)
  end

  defp maybe_validate_inclusion(changeset, field, allowed) do
    case get_field(changeset, field) do
      nil -> changeset
      _ -> validate_inclusion(changeset, field, allowed)
    end
  end
end
