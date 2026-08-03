defmodule Mehungry.Food.FoundementalFoodSpecies do
  @moduledoc """
  A fundamental food species — the botanical/zoological origin a USDA-backed
  ingredient ultimately maps to (e.g. "Apple", "Cattle"). `variety` narrows it
  (e.g. "Gala"); `scientific_name` and `family` are optional taxonomy.

  Its `foundemental_foods` are the concrete USDA ingredients curated onto it.
  """

  use Ecto.Schema

  import Ecto.Changeset

  schema "foundemental_food_species" do
    field :name, :string
    field :variety, :string
    field :alternative_name, :string
    field :scientific_name, :string
    field :family, :string

    has_many :foundemental_foods, Mehungry.Food.FoundementalFood,
      foreign_key: :foundemental_species_id

    has_many :translations, Mehungry.Food.FoundementalFoodSpeciesTranslation,
      foreign_key: :foundemental_species_id

    timestamps()
  end

  def changeset(species, attrs) do
    species
    |> cast(attrs, [:name, :variety, :alternative_name, :scientific_name, :family])
    |> cast_assoc(:translations,
      with: &Mehungry.Food.FoundementalFoodSpeciesTranslation.changeset/2,
      sort_param: :translations_sort,
      drop_param: :translations_drop
    )
    |> validate_required([:name])
    |> unique_constraint([:name, :variety])
  end
end
