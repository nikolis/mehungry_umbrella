defmodule Mehungry.Repo.Migrations.CreateProfessionalAppointments do
  use Ecto.Migration

  def change do
    create table(:professional_appointments) do
      add :professional_id, references(:users, on_delete: :delete_all), null: false
      add :client_id, references(:users, on_delete: :delete_all), null: false
      add :scheduled_at, :naive_datetime, null: false
      add :title, :string, null: false
      add :notes, :text

      timestamps()
    end

    create index(:professional_appointments, [:professional_id])
    create index(:professional_appointments, [:client_id])
    create index(:professional_appointments, [:scheduled_at])
  end
end
