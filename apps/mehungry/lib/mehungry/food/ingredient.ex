defmodule Mehungry.Food.Ingredient do
  use Ecto.Schema
  import Ecto.Changeset

  schema "ingredients" do
    field :description, :string
    field :name, :string
    field :url, :string

    belongs_to :category, Mehungry.Food.Category
    belongs_to :measurement_unit, Mehungry.Food.MeasurementUnit 
    has_many :ingredient_translation, Mehungry.Food.IngredientTranslation

    timestamps()
  end

  @doc false
  def changeset(ingredient, attrs) do
    ingredient
    |> cast(attrs, [:url, :name, :description, :measurement_unit_id, :category_id])
    |> cast_assoc(:ingredient_translation, with: &Mehungry.Food.IngredientTranslation.changeset/2)
    |> foreign_key_constraint(:category_id)
    |> validate_required([:name, :category_id, :measurement_unit_id])
    |> unique_constraint([:name])
  end
end
