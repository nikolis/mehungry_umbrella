defmodule Mehungry.Repo.Migrations.DropCustomObservabilityTables do
  use Ecto.Migration

  # The DIY observability system (MetricsBuffer snapshots, DIY error tracker,
  # query-time profiles) was removed in favour of a fresh start. Drop its tables.
  # Irreversible: the schemas and their create migrations are gone.
  def up do
    drop_if_exists table(:telemetry_snapshots)
    drop_if_exists table(:error_events)
    drop_if_exists table(:query_time_profiles)
  end

  def down do
    raise Ecto.MigrationError,
      message: "Cannot roll back: the custom observability system was removed."
  end
end
