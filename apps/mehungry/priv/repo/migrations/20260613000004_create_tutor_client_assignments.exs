defmodule Mehungry.Repo.Migrations.CreateTutorClientAssignments do
  use Ecto.Migration

  def change do
    create table(:tutor_client_assignments) do
      add :professional_id, references(:users, on_delete: :delete_all), null: false
      add :client_id, references(:users, on_delete: :delete_all), null: false

      timestamps()
    end

    # One active nutritionist max per client
    create unique_index(:tutor_client_assignments, [:client_id])
    create index(:tutor_client_assignments, [:professional_id])
  end
end
