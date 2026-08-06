defmodule Mehungry.Friends.FriendRequest do
  use Ecto.Schema
  import Ecto.Changeset

  schema "friend_requests" do
    field :status, :string, default: "pending"
    field :message, :string

    belongs_to :requester, Mehungry.Accounts.User
    belongs_to :recipient, Mehungry.Accounts.User

    timestamps()
  end

  def changeset(request, attrs) do
    request
    |> cast(attrs, [:requester_id, :recipient_id, :status, :message])
    |> validate_required([:requester_id, :recipient_id])
    |> validate_not_self()
    |> validate_inclusion(:status, ["pending", "accepted", "declined"])
    |> unique_constraint([:requester_id, :recipient_id])
    |> foreign_key_constraint(:requester_id)
    |> foreign_key_constraint(:recipient_id)
  end

  # A user cannot befriend themselves.
  defp validate_not_self(changeset) do
    requester_id = get_field(changeset, :requester_id)
    recipient_id = get_field(changeset, :recipient_id)

    if not is_nil(requester_id) and requester_id == recipient_id do
      add_error(changeset, :recipient_id, "cannot send a friend request to yourself")
    else
      changeset
    end
  end
end
