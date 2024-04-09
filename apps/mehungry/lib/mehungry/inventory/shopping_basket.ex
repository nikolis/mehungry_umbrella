defmodule Mehungry.Inventory.ShoppingBasket do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias Mehungry.Inventory.BasketIngredient
  alias Mehungry.Accounts.User

  schema "shopping_baskets" do
    field :end_dt, :naive_datetime
    field :start_dt, :naive_datetime
    field :title, :string

    belongs_to :user, User

    has_many :basket_ingredients, BasketIngredient, defaults: [], on_replace: :delete

    timestamps()
  end

  @doc false
  def changeset(shoping_basket, attrs) do
    shoping_basket
    |> cast(attrs, [:start_dt, :end_dt, :user_id, :title])
    |> cast_assoc(:basket_ingredients, with: &BasketIngredient.changeset/2)
    |> validate_required([:user_id, :title])
  end
end
