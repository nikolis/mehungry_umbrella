defmodule Mehungry.Food.FoundementalFoodSpeciesTranslation do
  @moduledoc """
  A per-language translation of a `FoundementalFoodSpecies` name (and optional
  description/url). Mirrors `Mehungry.Food.IngredientTranslation`: one row per
  `(species, language)`, keyed by the language's natural `name`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "foundemental_food_species_translations" do
    field :name, :string
    field :description, :string
    field :url, :string

    belongs_to :species, Mehungry.Food.FoundementalFoodSpecies,
      foreign_key: :foundemental_species_id

    belongs_to :language, Mehungry.Languages.Language,
      references: :name,
      foreign_key: :language_name,
      type: :string

    timestamps()
  end

  def changeset(translation, attrs) do
    translation
    |> cast(attrs, [:name, :language_name, :description, :url, :foundemental_species_id])
    |> validate_required([:name, :language_name])
    |> unique_constraint([:foundemental_species_id, :language_name])
  end
end
