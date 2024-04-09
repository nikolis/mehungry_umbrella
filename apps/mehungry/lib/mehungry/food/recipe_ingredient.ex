defmodule Mehungry.Food.RecipeIngredient do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  schema "recipe_ingredients" do
    field :quantity, :float
    field :ingredient_allias, :string

    field :delete, :boolean, virtual: true

    belongs_to :recipe, Mehungry.Food.Recipe
    belongs_to :measurement_unit, Mehungry.Food.MeasurementUnit
    belongs_to :ingredient, Mehungry.Food.Ingredient

    timestamps()
  end

  @doc false
  def changeset(recipe_ingredient, attrs) do

    changeset =
      recipe_ingredient
      |> cast(attrs, [
        :quantity,
        :ingredient_allias,
        :measurement_unit_id,
        :ingredient_id,
        :recipe_id,
        :delete
      ])
      |> validate_required([:ingredient_id, :quantity, :measurement_unit_id])
      |> foreign_key_constraint(:name)
      |> foreign_key_constraint(:recipe_ingredients_name_fkey)
      |> foreign_key_constraint(:recipe_ingredients_name)
      |> foreign_key_constraint(:recipe_ingredients)
      |> foreign_key_constraint(:ingredient_id)

    if get_change(changeset, :delete) do
      %{changeset | action: :delete}
    else
      changeset
    end
  end
end
