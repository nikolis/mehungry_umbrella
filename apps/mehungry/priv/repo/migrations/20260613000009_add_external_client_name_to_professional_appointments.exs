defmodule Mehungry.Repo.Migrations.AddExternalClientNameToProfessionalAppointments do
  use Ecto.Migration

  def change do
    alter table(:professional_appointments) do
      add :external_client_name, :string
    end

    execute(
      "ALTER TABLE professional_appointments ALTER COLUMN client_id DROP NOT NULL",
      "ALTER TABLE professional_appointments ALTER COLUMN client_id SET NOT NULL"
    )
  end
end
