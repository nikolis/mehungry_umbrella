defmodule Mehungry.Repo.Migrations.CreateSpeciesFactMiningRuns do
  use Ecto.Migration

  # Per-species tracking rows for a "Mine all species" fan-out: one row per
  # species per batch, grouped by `batch_id`. Each `SpeciesFactMiningWorker` job
  # advances its own row (pending → processing → completed | failed) and records
  # how many facts it stored. The admin LiveView streams these rows (O(1) patches)
  # and derives aggregate progress by counting over the current `batch_id` — so no
  # separate aggregate table is needed. Mirrors the per-unit tracking-row shape of
  # the S3 → USDA seed-import flow (see oban_ui_connected_worker.md).
  def change do
    create table(:species_fact_mining_runs) do
      add :batch_id, :string, null: false

      add :foundemental_species_id,
          references(:foundemental_food_species, on_delete: :delete_all),
          null: false

      add :status, :string, null: false, default: "pending"
      add :facts_total, :integer, null: false, default: 0
      add :verified_count, :integer, null: false, default: 0
      add :contradicted_count, :integer, null: false, default: 0
      add :error, :text
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime

      timestamps()
    end

    create index(:species_fact_mining_runs, [:batch_id])
    create index(:species_fact_mining_runs, [:status])

    create unique_index(:species_fact_mining_runs, [:batch_id, :foundemental_species_id],
             name: :species_fact_mining_runs_batch_species_index
           )
  end
end
