defmodule Mehungry.Repo.Migrations.CreateProfessionalCalendarBusy do
  use Ecto.Migration

  def change do
    # Local cache of a nutritionist's imported Google Calendar busy intervals.
    # Read by the slot engine so the public booking page never makes a live
    # Google call; replaced wholesale by GoogleCalendarBusyImportWorker.
    create table(:professional_calendar_busy) do
      add :professional_id, references(:users, on_delete: :delete_all), null: false
      add :starts_at, :utc_datetime, null: false
      add :ends_at, :utc_datetime, null: false

      timestamps()
    end

    create index(:professional_calendar_busy, [:professional_id])
    create index(:professional_calendar_busy, [:professional_id, :starts_at])
  end
end
