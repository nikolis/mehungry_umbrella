defmodule MehungryServer.Repo.Migrations.CreateMeasurementUnits do
  use Ecto.Migration

  def change do
    create table(:measurement_units) do
      add :url, :string
      add :name, :string

      timestamps()
    end
  end
end
