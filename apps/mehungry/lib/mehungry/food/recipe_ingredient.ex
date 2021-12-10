defmodule Mehungry.Food.RecipeIngredient do
  use Ecto.Schema
  import Ecto.Changeset
  alias Mehungry.Food.MeasurementUnit


  schema "recipe_ingredients" do
    field :quantity, :float
    field :ingredient_allias, :string    
    
    belongs_to :recipe, Mehungry.Food.Recipe
    belongs_to :measurement_unit, Mehungry.Food.MeasurementUnit
    belongs_to :ingredient, Mehungry.Food.Ingredient
    
    timestamps()
  end

  @doc false
  def changeset(recipe_ingredient, attrs) do
    """
      The attrs transformation code should be moved to the Food module
    """
    IO.inspect(recipe_ingredient)
    IO.inspect(attrs) 
    recipe_ingredient
    |> cast(attrs, [:quantity, :ingredient_allias, :measurement_unit_id, :ingredient_id, :recipe_id])
    |> validate_required([:quantity])
  end
end
