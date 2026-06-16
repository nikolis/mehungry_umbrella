defmodule Mehungry.Professionals.Appointment do
  use Ecto.Schema
  import Ecto.Changeset

  schema "professional_appointments" do
    field :scheduled_at, :naive_datetime
    field :ends_at, :naive_datetime
    field :title, :string
    field :notes, :string
    field :external_client_name, :string

    belongs_to :professional, Mehungry.Accounts.User
    belongs_to :client, Mehungry.Accounts.User

    timestamps()
  end

  def changeset(appointment, attrs) do
    appointment
    |> cast(attrs, [:professional_id, :client_id, :external_client_name, :scheduled_at, :ends_at, :title, :notes])
    |> validate_required([:professional_id, :scheduled_at, :title])
    |> validate_client_present()
    |> foreign_key_constraint(:professional_id)
    |> foreign_key_constraint(:client_id)
  end

  defp validate_client_present(changeset) do
    client_id = get_field(changeset, :client_id)
    external = get_field(changeset, :external_client_name)

    if is_nil(client_id) and (is_nil(external) or String.trim(external) == "") do
      add_error(changeset, :client_id, "must select a client or provide an external client name")
    else
      changeset
    end
  end
end
