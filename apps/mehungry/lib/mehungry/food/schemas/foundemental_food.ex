defmodule Mehungry.Food.FoundementalFood do
  @moduledoc """
  A concrete USDA-backed ingredient curated onto a `FoundementalFoodSpecies`.
  `usda_name` snapshots the ingredient's USDA description at curation time; the
  `ingredient_id` is unique so an ingredient belongs to at most one species.
  """

  use Ecto.Schema

  import Ecto.Changeset

  schema "foundemental_foods" do
    field :usda_name, :string

    belongs_to :species, Mehungry.Food.FoundementalFoodSpecies,
      foreign_key: :foundemental_species_id

    belongs_to :ingredient, Mehungry.Food.Ingredient

    timestamps()
  end

  def changeset(foundemental_food, attrs) do
    foundemental_food
    |> cast(attrs, [:foundemental_species_id, :usda_name, :ingredient_id])
    |> validate_required([:foundemental_species_id, :usda_name, :ingredient_id])
    |> foreign_key_constraint(:foundemental_species_id)
    |> foreign_key_constraint(:ingredient_id)
    |> unique_constraint(:ingredient_id)
  end
end
