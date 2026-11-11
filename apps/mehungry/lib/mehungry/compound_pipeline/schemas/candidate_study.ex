defmodule Mehungry.CompoundPipeline.CandidateStudy do
  @moduledoc """
  Reference-study provenance for a `CompoundPipeline.Candidate`: the `ScientificStudy`
  rows the co-occurrence evidence for the suggestion was extracted from. One row per
  `(candidate, study)`; refreshed on each derivation.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.CompoundPipeline.Candidate
  alias Mehungry.Literature.ScientificStudy

  schema "species_compound_candidate_studies" do
    belongs_to :candidate, Candidate
    belongs_to :study, ScientificStudy

    timestamps()
  end

  def changeset(candidate_study, attrs) do
    candidate_study
    |> cast(attrs, [:candidate_id, :study_id])
    |> validate_required([:candidate_id, :study_id])
    |> foreign_key_constraint(:candidate_id)
    |> foreign_key_constraint(:study_id)
    |> unique_constraint([:candidate_id, :study_id])
  end
end
