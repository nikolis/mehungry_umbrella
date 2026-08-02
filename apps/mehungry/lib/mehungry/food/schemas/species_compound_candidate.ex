defmodule Mehungry.Food.SpeciesCompoundCandidate do
  @moduledoc """
  A *proposed* `FoundementalFoodSpecies`↔`Compound` relationship derived from
  evidence (PubTator co-occurrence aggregated across the species' ingredients,
  species measurements, or manual import), scored and staged through
  `pending → promoted | rejected`.

  Species-keyed successor of `IngredientCompoundCandidate`: one suggestion per
  species instead of one per USDA ingredient variant. The reference studies a
  suggestion was extracted from are linked via `SpeciesCompoundCandidateStudy`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Food.{
    Compound,
    FoundementalFoodSpecies,
    SpeciesCompoundCandidateStudy,
    SpeciesCompoundRelationship
  }

  @relationship_types ~w(contains high_in low_in trace absent)
  @statuses ~w(pending promoted rejected)
  @evidence_levels ~w(strong moderate limited insufficient)
  @sources ~w(pubtator measurement manual)

  schema "species_compound_candidates" do
    field :relationship_type, :string, default: "contains"
    field :status, :string, default: "pending"
    field :evidence_score, :float, default: 0.0
    field :evidence_level, :string
    field :study_count, :integer, default: 0
    field :measurement_study_count, :integer, default: 0
    field :sources, {:array, :string}, default: []
    field :evidence, :map, default: %{}
    field :notes, :string

    belongs_to :species, FoundementalFoodSpecies, foreign_key: :foundemental_species_id
    belongs_to :compound, Compound
    belongs_to :promoted_relationship, SpeciesCompoundRelationship

    has_many :candidate_studies, SpeciesCompoundCandidateStudy, foreign_key: :candidate_id
    has_many :studies, through: [:candidate_studies, :study]

    timestamps()
  end

  @castable ~w(foundemental_species_id compound_id relationship_type status evidence_score
               evidence_level study_count measurement_study_count sources evidence
               notes promoted_relationship_id)a

  def changeset(candidate, attrs) do
    candidate
    |> cast(attrs, @castable)
    |> validate_required([:foundemental_species_id, :compound_id, :relationship_type, :status])
    |> validate_inclusion(:relationship_type, @relationship_types)
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:evidence_level, @evidence_levels)
    |> validate_subset(:sources, @sources)
    |> foreign_key_constraint(:foundemental_species_id)
    |> foreign_key_constraint(:compound_id)
    |> unique_constraint([:foundemental_species_id, :compound_id, :relationship_type],
      name: :species_compound_candidates_natural_key_index
    )
  end
end
