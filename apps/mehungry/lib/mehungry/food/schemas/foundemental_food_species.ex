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
    field :scientific_name, :string
    field :family, :string

    has_many :foundemental_foods, Mehungry.Food.FoundementalFood,
      foreign_key: :foundemental_species_id

    timestamps()
  end

  def changeset(species, attrs) do
    species
    |> cast(attrs, [:name, :variety, :scientific_name, :family])
    |> validate_required([:name])
    |> unique_constraint([:name, :variety])
  end
end
