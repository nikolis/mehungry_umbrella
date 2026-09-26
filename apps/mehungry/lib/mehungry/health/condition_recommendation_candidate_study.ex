defmodule Mehungry.Health.ConditionRecommendationCandidateStudy do
  @moduledoc """
  Provenance join between a `ConditionRecommendationCandidate` and the
  `ScientificStudy` it was extracted from — additive (each extraction POST links its
  study, `on_conflict: :nothing`). Frozen copies are made into
  `condition_state_recommendation_studies` at promotion.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Health.ConditionRecommendationCandidate
  alias Mehungry.Literature.ScientificStudy

  schema "condition_recommendation_candidate_studies" do
    belongs_to :candidate, ConditionRecommendationCandidate
    belongs_to :study, ScientificStudy

    timestamps()
  end

  def changeset(candidate_study, attrs) do
    candidate_study
    |> cast(attrs, [:candidate_id, :study_id])
    |> validate_required([:candidate_id, :study_id])
    |> unique_constraint([:candidate_id, :study_id],
      name: :condition_rec_candidate_studies_natural_key_index
    )
  end
end
