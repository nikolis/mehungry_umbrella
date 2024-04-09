defmodule Mehungry.History.RecipeUserMeal do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias Mehungry.Food.Recipe
  alias Mehungry.History.UserMeal
  alias Mehungry.History.ConsumeRecipeUserMeal

  schema "history_recipe_user_meals" do
    belongs_to :recipe, Recipe
    belongs_to :user_meal, UserMeal

    field :consume_portions, :integer
    field :cooking, :boolean
    field :cooking_portions, :integer

    field :delete, :boolean, virtual: true

    has_many :consume_recipe_user_meals, ConsumeRecipeUserMeal, on_replace: :delete
  end

  @doc false
  def changeset(recipe_user_meal, attrs) do
    changeset =
      recipe_user_meal
      |> cast(attrs, [
        :recipe_id,
        :user_meal_id,
        :cooking_portions,
        :cooking,
        :consume_portions,
        :delete
      ])
      |> validate_required([:recipe_id, :cooking_portions, :consume_portions])
      |> cast_assoc(:consume_recipe_user_meals,
        with: &ConsumeRecipeUserMeal.changeset/2,
        required: false
      )

    if get_change(changeset, :delete) do
      %{changeset | action: :delete}
    else
      changeset
    end
  end
end
