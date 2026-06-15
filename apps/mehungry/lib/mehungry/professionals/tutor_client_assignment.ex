defmodule Mehungry.Professionals.TutorClientAssignment do
  use Ecto.Schema
  import Ecto.Changeset

  schema "tutor_client_assignments" do
    belongs_to :professional, Mehungry.Accounts.User
    belongs_to :client, Mehungry.Accounts.User

    timestamps()
  end

  def changeset(assignment, attrs) do
    assignment
    |> cast(attrs, [:professional_id, :client_id])
    |> validate_required([:professional_id, :client_id])
    |> unique_constraint(:client_id)
    |> foreign_key_constraint(:professional_id)
    |> foreign_key_constraint(:client_id)
  end
end
