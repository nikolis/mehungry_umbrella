defmodule Mehungry.Food.SnackIngredient do
  @moduledoc """
  An ingredient an admin has marked as available to the AI meal-plan
  assistant as a snack, within a snack `kind`: `"dried_nut"` or `"fresh_fruit"`
  (fresh fruit is further gated by season — see `SnackIngredients.seasonal_fruit_ids/2`).
  Unique per `(ingredient_id, kind)`. Curated on `/professional/snack-nuts`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Accounts.User
  alias Mehungry.Food.Ingredient

  @kinds ~w(dried_nut fresh_fruit)

  schema "snack_ingredients" do
    field :kind, :string, default: "dried_nut"

    belongs_to :ingredient, Ingredient
    belongs_to :added_by, User

    timestamps()
  end

  def kinds, do: @kinds

  def changeset(row, attrs) do
    row
    |> cast(attrs, [:ingredient_id, :kind, :added_by_id])
    |> validate_required([:ingredient_id, :kind])
    |> validate_inclusion(:kind, @kinds)
    |> foreign_key_constraint(:ingredient_id)
    |> unique_constraint([:ingredient_id, :kind])
  end
end
