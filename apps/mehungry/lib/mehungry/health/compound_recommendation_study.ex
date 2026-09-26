defmodule Mehungry.Health.CompoundRecommendationStudy do
  @moduledoc """
  Frozen provenance join: a reference `ScientificStudy` (PubMed paper) cited by a
  promoted `CompoundRecommendation`.

  Mirrors `CompoundRecommendationCandidateStudy`, but with the opposite lifecycle:
  the candidate join is *refreshed* (delete + reinsert) on every derivation, whereas
  this set is written **once**, at human promotion, by copying the candidate's studies
  — and is never touched by re-derivation. It cites the exact papers the human
  validated, so the user-facing recommendation can always link back to its source.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Health.CompoundRecommendation
  alias Mehungry.Literature.ScientificStudy

  @type t :: %__MODULE__{}

  schema "compound_recommendation_studies" do
    belongs_to :recommendation, CompoundRecommendation
    belongs_to :study, ScientificStudy

    timestamps()
  end

  def changeset(recommendation_study, attrs) do
    recommendation_study
    |> cast(attrs, [:recommendation_id, :study_id])
    |> validate_required([:recommendation_id, :study_id])
    |> foreign_key_constraint(:recommendation_id)
    |> foreign_key_constraint(:study_id)
    |> unique_constraint([:recommendation_id, :study_id],
      name: :compound_recommendation_studies_natural_key_index
    )
  end
end
