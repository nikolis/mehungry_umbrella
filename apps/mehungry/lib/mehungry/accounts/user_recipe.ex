defmodule Mehungry.Accounts.UserRecipe do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias Mehungry.Food.Recipe
  alias Mehungry.Accounts.User

  schema "user_recipes" do
    belongs_to :user, User
    belongs_to :recipe, Recipe

    timestamps()
  end

  @doc false
  def changeset(user_recipe, attrs) do
    user_recipe
    |> cast(attrs, [
      :user_id,
      :recipe_id
    ])
    |> validate_required([:user_id, :recipe_id])
  end
end
