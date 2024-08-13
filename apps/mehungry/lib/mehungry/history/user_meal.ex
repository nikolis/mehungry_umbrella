defmodule Mehungry.History.UserMeal do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.History.ConsumeRecipeUserMeal
  alias Mehungry.History.RecipeUserMeal

  schema "history_user_meals" do
    field :start_dt, :naive_datetime
    field :end_dt, :naive_datetime
    field :title, :string
    field :user_id, :id

    has_many :recipe_user_meals, RecipeUserMeal, on_replace: :delete, on_delete: :nothing

    has_many :consume_recipe_user_meals, ConsumeRecipeUserMeal,
      on_replace: :delete,
      on_delete: :nothing

    timestamps()
  end

  @doc false
  def changeset(user_meal, attrs) do
    user_meal
    |> cast(attrs, [:title, :start_dt, :end_dt, :user_id])
    |> cast_assoc(:recipe_user_meals, with: &RecipeUserMeal.changeset/2, required: false)
    |> cast_assoc(:consume_recipe_user_meals,
      with: &ConsumeRecipeUserMeal.changeset/2,
      required: false
    )
    |> validate_required([:title, :user_id])
  end
end
