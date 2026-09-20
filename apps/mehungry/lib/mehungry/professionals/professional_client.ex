defmodule Mehungry.Professionals.ProfessionalClient do
  @moduledoc """
  A nutritionist-owned client file ("patient record").

  Like `TutorClientAssignment`, a `ProfessionalClient` is always anchored to a
  registered platform `User` (`user_id`) — a record is **never headless**. On
  top of that association it holds the client's dietary-history PII directly
  (name, contact, anthropometrics, consultation notes).
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Mehungry.Professionals.{ClientIntake, ConsultationNote}

  schema "professional_clients" do
    field :full_name, :string
    field :date_of_birth, :date
    field :email, :string
    field :phone, :string
    field :address, :string
    field :postal_code, :string
    field :work_schedule, :string

    belongs_to :professional, Mehungry.Accounts.User
    belongs_to :user, Mehungry.Accounts.User

    has_many :intakes, ClientIntake
    has_many :consultation_notes, ConsultationNote

    timestamps()
  end

  def changeset(client, attrs) do
    client
    |> cast(attrs, [
      :professional_id,
      :user_id,
      :full_name,
      :date_of_birth,
      :email,
      :phone,
      :address,
      :postal_code,
      :work_schedule
    ])
    |> validate_required([:professional_id, :user_id, :full_name])
    |> foreign_key_constraint(:professional_id)
    |> foreign_key_constraint(:user_id)
  end
end
