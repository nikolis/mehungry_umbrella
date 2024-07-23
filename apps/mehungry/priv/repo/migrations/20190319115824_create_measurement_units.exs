defmodule MehungryServer.Repo.Migrations.CreateMeasurementUnits do
  use Ecto.Migration

  def change do
    create table(:measurement_units) do
      add :url, :string
      add :name, :string
      add :alternate_name, :string

      timestamps()
    end

    create unique_index(:measurement_units, [:name])
  end
end
