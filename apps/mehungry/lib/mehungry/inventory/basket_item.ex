defmodule Mehungry.Inventory.BasketItem do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias Mehungry.Food.MeasurementUnit
  alias Mehungry.Food.Ingredient
  alias Mehungry.Food.Recipe
  alias Mehungry.Inventory.ShoppingBasket

  schema "basket_items" do
    field :quantity, :float
    field :in_storage, :boolean, default: false
    field :name, :string
    field :nutrition_data, :map, default: %{}
    field :usda_fdc_id, :integer

    belongs_to :measurement_unit, MeasurementUnit
    belongs_to :shopping_basket, ShoppingBasket
    belongs_to :recipe, Recipe

    timestamps()
  end

  @doc false
  def changeset(basket_ingredient, attrs) do
    attrs
    |> IO.inspect(label: "Ceate item")

    basket_ingredient
    |> cast(attrs, [
      :quantity,
      :in_storage,
      :usda_fdc_id,
      :name,
      :recipe_id,
      :shopping_basket_id,
      :measurement_unit_id
    ])
    |> validate_required([:quantity, :name])
  end
end
