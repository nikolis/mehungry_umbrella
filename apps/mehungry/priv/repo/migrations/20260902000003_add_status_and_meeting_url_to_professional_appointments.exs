defmodule Mehungry.Repo.Migrations.AddStatusAndMeetingUrlToProfessionalAppointments do
  use Ecto.Migration

  def change do
    alter table(:professional_appointments) do
      add :status, :string, null: false, default: "requested"
      add :meeting_url, :string
    end

    create index(:professional_appointments, [:professional_id, :status, :scheduled_at])
  end
end
