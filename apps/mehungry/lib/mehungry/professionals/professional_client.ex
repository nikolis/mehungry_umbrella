defmodule Mehungry.Professionals.ProfessionalClient do
  @moduledoc """
  A nutritionist-owned client file ("patient record").

  Unlike `TutorClientAssignment` (which links a professional to a registered
  platform `User`), a `ProfessionalClient` is an off-platform person the
  nutritionist keeps a dietary history for — holding their PII directly and
  optionally linking to a platform account via `user_id`.
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
    |> validate_required([:professional_id, :full_name])
    |> foreign_key_constraint(:professional_id)
    |> foreign_key_constraint(:user_id)
  end
end
