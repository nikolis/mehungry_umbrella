defmodule Mehungry.Repo.Migrations.CreateProfessionalAvailabilities do
  use Ecto.Migration

  def change do
    create table(:professional_availabilities) do
      add :professional_id, references(:users, on_delete: :delete_all), null: false
      add :day_of_week, :integer, null: false
      add :start_time, :time, null: false
      add :end_time, :time, null: false

      timestamps()
    end

    create index(:professional_availabilities, [:professional_id])
  end
end
