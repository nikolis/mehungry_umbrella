defmodule Mehungry.Health.ConditionStateRecommendationStudy do
  @moduledoc """
  Frozen PubMed-provenance join between a `ConditionStateRecommendation` and a
  `ScientificStudy` — copied once at promotion from the backing candidate's studies
  and never touched by re-extraction, so a promoted recommendation keeps citing
  exactly the papers the admin validated. Mirrors `CompoundRecommendationStudy`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Health.ConditionStateRecommendation
  alias Mehungry.Literature.ScientificStudy

  schema "condition_state_recommendation_studies" do
    belongs_to :recommendation, ConditionStateRecommendation
    belongs_to :study, ScientificStudy

    timestamps()
  end

  def changeset(recommendation_study, attrs) do
    recommendation_study
    |> cast(attrs, [:recommendation_id, :study_id])
    |> validate_required([:recommendation_id, :study_id])
    |> unique_constraint([:recommendation_id, :study_id],
      name: :condition_state_recommendation_studies_natural_key_index
    )
  end
end
