defmodule Mehungry.Health.CompoundRecommendationCandidateStudy do
  @moduledoc """
  Provenance join: one reference `ScientificStudy` cited by a
  `CompoundRecommendationCandidate`. Mirrors `SpeciesCompoundCandidateStudy` — the
  set is refreshed (delete + reinsert) on every derivation so it always reflects the
  studies whose relations currently back the candidate.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Health.CompoundRecommendationCandidate
  alias Mehungry.Literature.ScientificStudy

  @type t :: %__MODULE__{}

  schema "compound_recommendation_candidate_studies" do
    belongs_to :candidate, CompoundRecommendationCandidate
    belongs_to :study, ScientificStudy

    timestamps()
  end

  def changeset(candidate_study, attrs) do
    candidate_study
    |> cast(attrs, [:candidate_id, :study_id])
    |> validate_required([:candidate_id, :study_id])
    |> unique_constraint([:candidate_id, :study_id])
  end
end
