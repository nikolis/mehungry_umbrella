defmodule Mehungry.Professionals.ConsultationNote do
  @moduledoc """
  A clinical progress note recorded for a completed visit of a
  `ProfessionalClient`. Distinct from `Appointment` (which handles the booking
  lifecycle) — a note may optionally reference a booked appointment.

  `visit_number` is intentionally not unique: real-world histories skip and
  repeat numbers.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @modalities ~w(in_person phone online)

  def modalities, do: @modalities

  schema "consultation_notes" do
    field :visit_number, :integer
    field :visit_date, :date
    field :modality, :string, default: "in_person"
    field :body, :string
    field :todo, :string
    field :weight_kg, :float
    field :details, :map, default: %{}

    belongs_to :professional_client, Mehungry.Professionals.ProfessionalClient
    belongs_to :appointment, Mehungry.Professionals.Appointment

    timestamps()
  end

  def changeset(note, attrs) do
    note
    |> cast(attrs, [
      :professional_client_id,
      :appointment_id,
      :visit_number,
      :visit_date,
      :modality,
      :body,
      :todo,
      :weight_kg,
      :details
    ])
    |> validate_required([:professional_client_id])
    |> validate_inclusion(:modality, @modalities)
    |> foreign_key_constraint(:professional_client_id)
    |> foreign_key_constraint(:appointment_id)
  end
end
