defmodule Mehungry.Food.SpeciesCompoundRelationshipStudy do
  @moduledoc """
  Frozen provenance join: a reference `ScientificStudy` (PubMed paper) cited by a
  promoted `SpeciesCompoundRelationship` fact.

  Mirrors `SpeciesCompoundCandidateStudy`, but written **once** at promotion (copied
  from the candidate's co-occurrence studies) and never refreshed by re-derivation, so
  the curated fact keeps citing exactly the papers it was promoted from.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Food.SpeciesCompoundRelationship
  alias Mehungry.Literature.ScientificStudy

  @type t :: %__MODULE__{}

  schema "species_compound_relationship_studies" do
    belongs_to :relationship, SpeciesCompoundRelationship
    belongs_to :study, ScientificStudy

    timestamps()
  end

  def changeset(relationship_study, attrs) do
    relationship_study
    |> cast(attrs, [:relationship_id, :study_id])
    |> validate_required([:relationship_id, :study_id])
    |> foreign_key_constraint(:relationship_id)
    |> foreign_key_constraint(:study_id)
    |> unique_constraint([:relationship_id, :study_id],
      name: :species_compound_relationship_studies_natural_key_index
    )
  end
end
