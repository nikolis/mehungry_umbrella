defmodule Mehungry.History.FreeFoodUserMeal do
  @moduledoc """
  An arbitrary ("free food") calendar entry — a food the user logs that is NOT in
  our database (e.g. fast food they picked up). Fully self-contained: its only
  association is back to the `UserMeal`, so it never creates or references
  `Recipe`/`Ingredient` rows and never surfaces outside the owner's calendar.

  Nutrition is client-supplied per-100g (`nutrients_per_100g`) and scaled by the
  resolved `grams` at read time — the REST client is the source of truth for the
  nutrition of an unknown food. `portion_*` fields are display/round-trip only;
  `grams` is the scaling source of truth (resolved server-side from grams mode or
  `portion_grams * portions`).
  """

  use Ecto.Schema

  alias Mehungry.History.UserMeal

  import Ecto.Changeset

  schema "history_free_food_user_meals" do
    belongs_to :user_meal, UserMeal

    field :name, :string
    field :grams, :float
    field :nutrients_per_100g, :map

    field :portion_name, :string
    field :portion_grams, :float
    field :portions, :float

    field :delete, :boolean, virtual: true
  end

  @doc false
  def changeset(free_food_user_meal, attrs) do
    changeset =
      free_food_user_meal
      |> cast(attrs, [
        :user_meal_id,
        :name,
        :grams,
        :nutrients_per_100g,
        :portion_name,
        :portion_grams,
        :portions,
        :delete
      ])
      |> validate_required([:name, :grams, :nutrients_per_100g])
      |> validate_number(:grams, greater_than: 0)

    if get_change(changeset, :delete) do
      %{changeset | action: :delete}
    else
      changeset
    end
  end
end
