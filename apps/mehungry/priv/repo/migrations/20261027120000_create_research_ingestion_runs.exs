defmodule Mehungry.Repo.Migrations.CreateResearchIngestionRuns do
  use Ecto.Migration

  # Durable progress record for one admin-triggered "run the research pipeline"
  # pass (crawl? + extractor /analyze + store, across conditions). One job per run
  # (sequential orchestrator); the row is the UI's source of truth for live
  # progress on /professional/health. See
  # docs/features/professionals/research_search.md §7.
  def change do
    create table(:research_ingestion_runs) do
      add :status, :string, null: false, default: "processing"
      add :options, :map, null: false, default: %{}
      add :conditions_total, :integer, null: false, default: 0
      add :conditions_done, :integer, null: false, default: 0
      add :current_condition, :string
      add :inserted, :integer, null: false, default: 0
      add :updated, :integer, null: false, default: 0
      add :unchanged, :integer, null: false, default: 0
      add :skipped, :integer, null: false, default: 0
      add :error, :string
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime

      timestamps()
    end
  end
end
