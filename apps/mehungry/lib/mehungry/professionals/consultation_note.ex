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
    field :body_fat_percentage, :float
    field :waist_cm, :float
    field :muscle_mass_kg, :float
    field :hands_cm, :float
    field :glutes_cm, :float
    field :feet_cm, :float
    field :bmi, :float
    field :bmr_kcal, :integer
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
      :body_fat_percentage,
      :waist_cm,
      :muscle_mass_kg,
      :hands_cm,
      :glutes_cm,
      :feet_cm,
      :bmi,
      :bmr_kcal,
      :details
    ])
    |> validate_required([:professional_client_id])
    |> validate_inclusion(:modality, @modalities)
    |> validate_number(:weight_kg, greater_than: 0)
    |> validate_number(:body_fat_percentage,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 100
    )
    |> validate_number(:waist_cm, greater_than: 0)
    |> validate_number(:muscle_mass_kg, greater_than: 0)
    |> validate_number(:hands_cm, greater_than: 0)
    |> validate_number(:glutes_cm, greater_than: 0)
    |> validate_number(:feet_cm, greater_than: 0)
    |> foreign_key_constraint(:professional_client_id)
    |> foreign_key_constraint(:appointment_id)
  end
end
