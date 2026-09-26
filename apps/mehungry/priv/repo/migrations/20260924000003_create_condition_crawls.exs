defmodule Mehungry.Repo.Migrations.CreateConditionCrawls do
  use Ecto.Migration

  # The reverse (condition-seeded) literature crawl — the condition analogue of the
  # species crawl's `literature_crawl_attempts` / `literature_crawl_runs`. Discovers
  # studies *about a condition* (name × dietary/phase terms) and links them via
  # `study_conditions`, feeding the phase-aware recommendation extraction pipeline.
  def up do
    # Per-(condition, search_term) ledger — lets the batch worker terminate and is the
    # incremental-crawl watermark (last_crawled_at), mirroring literature_crawl_attempts.
    create table(:condition_crawl_attempts) do
      add :condition_id, references(:conditions, on_delete: :delete_all), null: false
      add :search_term, :string, null: false
      add :outcome, :string, null: false
      add :studies_found, :integer, default: 0
      add :last_crawled_at, :utc_datetime

      timestamps()
    end

    create unique_index(:condition_crawl_attempts, [:condition_id, :search_term])

    # Aggregate progress record for one condition-crawl pass (pending → processing →
    # completed | failed), broadcast on every transition — mirrors literature_crawl_runs.
    create table(:condition_crawl_runs) do
      add :status, :string, null: false, default: "pending"
      add :processed, :integer
      add :total, :integer
      add :studies_found, :integer
      add :error, :string
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime

      timestamps()
    end
  end

  def down do
    drop table(:condition_crawl_runs)
    drop table(:condition_crawl_attempts)
  end
end
