defmodule Mehungry.Professionals.Appointment do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(requested accepted declined cancelled)

  def statuses, do: @statuses

  schema "professional_appointments" do
    field :scheduled_at, :naive_datetime
    field :ends_at, :naive_datetime
    field :title, :string
    field :notes, :string
    field :external_client_name, :string
    field :status, :string, default: "requested"
    field :meeting_url, :string

    belongs_to :professional, Mehungry.Accounts.User
    belongs_to :client, Mehungry.Accounts.User

    timestamps()
  end

  def changeset(appointment, attrs) do
    appointment
    |> cast(attrs, [
      :professional_id,
      :client_id,
      :external_client_name,
      :scheduled_at,
      :ends_at,
      :title,
      :notes,
      :status,
      :meeting_url
    ])
    |> validate_required([:professional_id, :scheduled_at, :title])
    |> validate_inclusion(:status, @statuses)
    |> validate_client_present()
    |> foreign_key_constraint(:professional_id)
    |> foreign_key_constraint(:client_id)
  end

  @doc "Changeset for a status transition (accept/decline/cancel), optionally attaching a meeting URL."
  def status_changeset(appointment, attrs) do
    appointment
    |> cast(attrs, [:status, :meeting_url])
    |> validate_required([:status])
    |> validate_inclusion(:status, @statuses)
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
