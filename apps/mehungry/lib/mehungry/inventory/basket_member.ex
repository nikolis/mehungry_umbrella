defmodule Mehungry.Inventory.BasketMember do
  @moduledoc """
  A person a shopping list is shared with. The list's owner stays on
  `shopping_baskets.user_id` and has no row here. See
  `docs/features/shared_basket.md`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Mehungry.Accounts.User
  alias Mehungry.Inventory.ShoppingBasket

  schema "shopping_basket_members" do
    belongs_to :shopping_basket, ShoppingBasket
    belongs_to :user, User
    belongs_to :invited_by, User

    timestamps()
  end

  @doc false
  def changeset(member, attrs) do
    member
    |> cast(attrs, [:shopping_basket_id, :user_id, :invited_by_id])
    |> validate_required([:shopping_basket_id, :user_id])
    |> unique_constraint([:shopping_basket_id, :user_id])
  end
end
