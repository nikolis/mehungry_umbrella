defmodule Mehungry.Inventory.ShoppingBasket do
  use Ecto.Schema
  import Ecto.Changeset

  alias Mehungry.Inventory.BasketIngredient
  alias Mehungry.Accounts.User

  schema "shopping_baskets" do
    field :end_dt, :naive_datetime
    field :start_dt, :naive_datetime

    belongs_to :user, User

    has_many :basket_ingredients, BasketIngredient, on_replace: :delete

    timestamps()
  end

  @doc false
  def changeset(shoping_basket, attrs) do
    shoping_basket
    |> cast(attrs, [:start_dt, :end_dt, :user_id])
    |> cast_assoc(:basket_ingredients, with: &BasketIngredient.changeset/2)
    |> validate_required([:start_dt, :end_dt, :user_id])
  end
end
