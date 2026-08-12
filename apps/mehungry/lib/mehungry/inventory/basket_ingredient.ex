defmodule Mehungry.Inventory.BasketIngredient do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias Mehungry.Food.MeasurementUnit
  alias Mehungry.Food.Ingredient
  alias Mehungry.Inventory.ShoppingBasket

  schema "basket_ingredients" do
    field :quantity, :float
    field :in_storage, :boolean, default: false
    # Free-text unit label for description-only portions (no measurement unit).
    field :description, :string

    belongs_to :measurement_unit, MeasurementUnit
    belongs_to :ingredient, Ingredient
    belongs_to :shopping_basket, ShoppingBasket

    timestamps()
  end

  @doc false
  def changeset(basket_ingredient, attrs) do
    basket_ingredient
    |> cast(attrs, [
      :quantity,
      :in_storage,
      :ingredient_id,
      :shopping_basket_id,
      :measurement_unit_id,
      :description
    ])
    |> validate_required([:quantity, :ingredient_id])
  end
end
