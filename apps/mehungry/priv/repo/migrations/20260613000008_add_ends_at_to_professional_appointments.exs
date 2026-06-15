defmodule Mehungry.Repo.Migrations.AddEndsAtToProfessionalAppointments do
  use Ecto.Migration

  def change do
    alter table(:professional_appointments) do
      add :ends_at, :naive_datetime
    end
  end
end
