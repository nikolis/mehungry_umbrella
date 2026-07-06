defmodule Mehungry.Repo.Migrations.CreateTelemetrySnapshots do
  use Ecto.Migration

  def change do
    create table(:telemetry_snapshots) do
      add :metric, :string, null: false
      add :tags, :map, default: %{}
      add :period_start, :utc_datetime, null: false
      add :min, :float
      add :avg, :float
      add :max, :float
      add :p95, :float
      add :sample_count, :integer, default: 0
    end

    create index(:telemetry_snapshots, [:metric, :period_start])
    create index(:telemetry_snapshots, [:period_start])
  end
end
