defmodule Mehungry.Inventory.BasketInvitation do
  @moduledoc """
  A single-use, expiring invitation to share a shopping list. Only the SHA-256
  of the link token is stored. `invitee_user_id` is set when the invitation was
  addressed to an email that belongs to an existing account, which lets that
  user answer it in-app without the link. See `docs/features/shared_basket.md`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Mehungry.Accounts.User
  alias Mehungry.Inventory.ShoppingBasket

  @statuses ~w(pending accepted declined revoked)

  schema "shopping_basket_invitations" do
    field :invitee_email, :string
    field :token_hash, :binary, redact: true
    field :status, :string, default: "pending"
    field :expires_at, :utc_datetime

    belongs_to :shopping_basket, ShoppingBasket
    belongs_to :inviter, User
    belongs_to :invitee_user, User
    belongs_to :accepted_by, User

    timestamps()
  end

  @doc false
  def changeset(invitation, attrs) do
    invitation
    |> cast(attrs, [
      :shopping_basket_id,
      :inviter_id,
      :invitee_email,
      :invitee_user_id,
      :token_hash,
      :status,
      :expires_at,
      :accepted_by_id
    ])
    |> validate_required([:shopping_basket_id, :inviter_id, :token_hash, :expires_at])
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint(:token_hash)
  end
end
