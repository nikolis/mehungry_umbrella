defmodule Mehungry.Repo.Migrations.AddGoogleEventIdToProfessionalAppointments do
  use Ecto.Migration

  def change do
    alter table(:professional_appointments) do
      # Google Calendar event id for an accepted appointment pushed to the
      # nutritionist's calendar, so it can be updated/deleted on change.
      add :google_event_id, :string
    end
  end
end
