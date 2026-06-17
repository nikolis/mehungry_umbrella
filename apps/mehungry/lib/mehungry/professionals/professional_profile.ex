defmodule Mehungry.Professionals.ProfessionalProfile do
  use Ecto.Schema
  import Ecto.Changeset

  schema "professional_profiles" do
    field :specialization, :string
    field :bio, :string

    belongs_to :user, Mehungry.Accounts.User

    timestamps()
  end

  def changeset(profile, attrs) do
    profile
    |> cast(attrs, [:user_id, :specialization, :bio])
    |> validate_required([:user_id, :specialization])
    |> validate_length(:specialization, max: 100)
    |> unique_constraint(:user_id)
    |> foreign_key_constraint(:user_id)
  end
end
