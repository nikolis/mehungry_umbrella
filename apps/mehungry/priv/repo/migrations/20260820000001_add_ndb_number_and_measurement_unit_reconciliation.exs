defmodule Mehungry.Repo.Migrations.AddNdbNumberAndMeasurementUnitReconciliation do
  use Ecto.Migration

  # Some measurement units were seeded with a bare USDA NDB number as their name
  # (e.g. "10205" — really "NDB Number: 10205"). `ndb_number` preserves that code
  # after the name is reconciled to the real USDA food description, and the
  # reconciliation-run table tracks the batch USDA-lookup pass for a live progress
  # bar, mirroring `nutrient_recalculation_runs`.
  def change do
    alter table(:measurement_units) do
      add :ndb_number, :string
    end

    create index(:measurement_units, [:ndb_number])

    create table(:measurement_unit_reconciliation_runs) do
      add :status, :string, null: false, default: "processing"
      add :total, :integer, null: false, default: 0
      add :completed, :integer, null: false, default: 0
      add :failed, :integer, null: false, default: 0
      add :error, :text
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime

      timestamps()
    end

    create index(:measurement_unit_reconciliation_runs, [:status])
  end
end
