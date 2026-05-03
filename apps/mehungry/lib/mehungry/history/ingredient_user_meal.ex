defmodule Mehungry.History.IngredientUserMeal do
  @moduledoc false

  use Ecto.Schema

  alias Mehungry.Food.Ingredient
  alias Mehungry.History.UserMeal

  import Ecto.Changeset

  schema "history_ingredient_user_meals" do
    belongs_to :ingredient, Ingredient
    belongs_to :user_meal, UserMeal
    belongs_to :measurement_unit, Mehungry.Food.MeasurementUnit

    field :quantity, :float
  end

  @doc false
  def changeset(ingredient_user_meal, attrs) do
    changeset =
      ingredient_user_meal
      |> cast(attrs, [
        :ingredient_id,
        :user_meal_id,
        :measurement_unit_id,
        :quantity
      ])
      |> validate_required([:quantity, :measurement_unit_id, :ingredient_id])

    if get_change(changeset, :delete) do
      %{changeset | action: :delete}
    else
      changeset
    end
  end
end
