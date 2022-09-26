defmodule Mehungry.History.UserMeal do
  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.History.RecipeUserMeal

  schema "history_user_meals" do
    field :meal_datetime, :utc_datetime
    field :title, :string
    field :user_id, :id

    has_many :recipe_user_meals, RecipeUserMeal, on_replace: :delete

    timestamps()
  end

  @doc false
  def changeset(user_meal, attrs) do
    user_meal
    |> cast(attrs, [:title, :meal_datetime])
    |> cast_assoc(:recipe_user_meals, with: &RecipeUserMeal.changeset/2)
    |> validate_required([:title])
  end
end
