defmodule Mehungry.Repo.Migrations.CreateSpeciesEnrichmentRuns do
  use Ecto.Migration

  # Per-species tracking rows for an "Enrich all species" fan-out: one row per
  # species per batch, grouped by `batch_id`. Each `SpeciesEnrichmentWorker` job
  # advances its own row (pending → processing → completed | failed) and records how
  # many facts it upserted per source (Wikidata + FAOSTAT). The admin LiveView streams
  # these rows (O(1) patches) and derives aggregate progress by counting over the
  # current `batch_id`. Mirrors the "Mine all species" tracking rows
  # (species_fact_mining_runs) and the S3 → USDA seed-import flow
  # (see oban_ui_connected_worker.md).
  def change do
    create table(:species_enrichment_runs) do
      add :batch_id, :string, null: false

      add :foundemental_species_id,
          references(:foundemental_food_species, on_delete: :delete_all),
          null: false

      add :status, :string, null: false, default: "pending"
      add :wikidata_count, :integer, null: false, default: 0
      add :faostat_count, :integer, null: false, default: 0
      add :error, :text
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime

      timestamps()
    end

    create index(:species_enrichment_runs, [:batch_id])
    create index(:species_enrichment_runs, [:status])

    create unique_index(:species_enrichment_runs, [:batch_id, :foundemental_species_id],
             name: :species_enrichment_runs_batch_species_index
           )
  end
end
