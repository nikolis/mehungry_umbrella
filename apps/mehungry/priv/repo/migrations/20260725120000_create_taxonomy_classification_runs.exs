defmodule Mehungry.Repo.Migrations.CreateTaxonomyClassificationRuns do
  use Ecto.Migration

  # Durable per-run tracking for the taxonomy classification flow. One row per
  # "Run Classification" click; `status` walks pending -> processing ->
  # completed | failed across the self-re-enqueueing worker batches, and
  # `classified`/`total` hold a coverage snapshot so TaxonomyReview can render a
  # live progress bar. Mirrors `seed_files` for the S3 ingredient-seeding flow.
  def change do
    create table(:taxonomy_classification_runs) do
      add :taxonomy_id, references(:taxonomies, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "pending"
      add :classified, :integer
      add :total, :integer
      add :error, :text
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime

      timestamps()
    end

    create index(:taxonomy_classification_runs, [:taxonomy_id])
  end
end
