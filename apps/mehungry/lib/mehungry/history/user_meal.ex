defmodule Mehungry.History.UserMeal do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.History.RecipeUserMeal

  schema "history_user_meals" do
    field :start_dt, :naive_datetime
    field :end_dt, :naive_datetime
    field :title, :string
    field :user_id, :id

    has_many :recipe_user_meals, RecipeUserMeal, on_replace: :delete

    timestamps()
  end

  @doc false
  def changeset(user_meal, attrs) do
    user_meal
    |> cast(attrs, [:title, :start_dt, :end_dt, :user_id])
    |> cast_assoc(:recipe_user_meals, with: &RecipeUserMeal.changeset/2)
    |> validate_required([:title, :user_id])
  end
end
