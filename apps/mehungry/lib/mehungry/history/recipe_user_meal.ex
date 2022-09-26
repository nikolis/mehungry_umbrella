defmodule Mehungry.History.RecipeUserMeal do
  use Ecto.Schema
  import Ecto.Changeset

  alias Mehungry.Food.Recipe
  alias Mehungry.History.UserMeal

  schema "history_recipe_user_meals" do
    belongs_to :recipe, Recipe
    belongs_to :user_meal, UserMeal
  end

  @doc false
  def changeset(recipe_user_meal, attrs) do
    recipe_user_meal
    |> cast(attrs, [:recipe_id, :user_meal_id])
    |> validate_required([])
  end
end
