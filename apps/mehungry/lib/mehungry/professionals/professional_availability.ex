defmodule Mehungry.Professionals.ProfessionalAvailability do
  use Ecto.Schema
  import Ecto.Changeset

  @moduledoc """
  A recurring weekly availability window for a nutritionist. `day_of_week` is
  0 (Sunday) .. 6 (Saturday); `start_time`/`end_time` are wall-clock times in
  the professional's declared timezone. The public booking calendar slices each
  window into `appointment_slot_minutes` slots (from the profile) and subtracts
  already-booked appointments.
  """

  schema "professional_availabilities" do
    field :day_of_week, :integer
    field :start_time, :time
    field :end_time, :time

    belongs_to :professional, Mehungry.Accounts.User

    timestamps()
  end

  def changeset(availability, attrs) do
    availability
    |> cast(attrs, [:professional_id, :day_of_week, :start_time, :end_time])
    |> validate_required([:professional_id, :day_of_week, :start_time, :end_time])
    |> validate_inclusion(:day_of_week, 0..6)
    |> validate_end_after_start()
    |> foreign_key_constraint(:professional_id)
  end

  defp validate_end_after_start(changeset) do
    start_time = get_field(changeset, :start_time)
    end_time = get_field(changeset, :end_time)

    if start_time && end_time && Time.compare(end_time, start_time) != :gt do
      add_error(changeset, :end_time, "must be after the start time")
    else
      changeset
    end
  end
end
