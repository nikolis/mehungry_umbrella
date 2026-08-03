defmodule Mehungry.Food.SpeciesCompoundRelationship do
  @moduledoc """
  A curated `FoundementalFoodSpecies`↔`Compound` fact (e.g. *Apricot contains
  Flavonoids*) — the species-keyed successor of `IngredientCompoundRelationship`.

  This is the fact layer stage-4 promotion writes and that `Mehungry.Health`
  reads: conditions resolve to **species**, and the implicated ingredients are
  derived only through the species that carries the compound.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Food.{Compound, FoundementalFoodSpecies}

  @relationship_types ~w(contains high_in low_in trace absent)
  @sources ~w(manual ai literature external_db)

  schema "species_compound_relationships" do
    field :relationship_type, :string, default: "contains"
    field :confidence, :float
    field :source, :string
    field :notes, :string

    belongs_to :species, FoundementalFoodSpecies, foreign_key: :foundemental_species_id
    belongs_to :compound, Compound

    timestamps()
  end

  @castable ~w(foundemental_species_id compound_id relationship_type confidence source notes)a

  def changeset(relationship, attrs) do
    relationship
    |> cast(attrs, @castable)
    |> validate_required([:foundemental_species_id, :compound_id, :relationship_type, :source])
    |> validate_inclusion(:relationship_type, @relationship_types)
    |> validate_inclusion(:source, @sources)
    |> foreign_key_constraint(:foundemental_species_id)
    |> foreign_key_constraint(:compound_id)
    |> unique_constraint([:foundemental_species_id, :compound_id, :relationship_type, :source],
      name: :species_compound_relationships_natural_key_index
    )
  end
end
