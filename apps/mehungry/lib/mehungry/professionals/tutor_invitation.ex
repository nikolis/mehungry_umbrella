defmodule Mehungry.Professionals.TutorInvitation do
  use Ecto.Schema
  import Ecto.Changeset

  schema "tutor_invitations" do
    field :status, :string, default: "pending"
    field :message, :string

    belongs_to :professional, Mehungry.Accounts.User
    belongs_to :client, Mehungry.Accounts.User

    timestamps()
  end

  def changeset(invitation, attrs) do
    invitation
    |> cast(attrs, [:professional_id, :client_id, :status, :message])
    |> validate_required([:professional_id, :client_id])
    |> validate_inclusion(:status, ["pending", "accepted", "declined"])
    |> unique_constraint([:professional_id, :client_id])
    |> foreign_key_constraint(:professional_id)
    |> foreign_key_constraint(:client_id)
  end
end
