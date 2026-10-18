defmodule Mehungry.Repo.Migrations.CreateDailySessionMetrics do
  use Ecto.Migration

  # Anonymous, consent-independent session metrics. One row per calendar day in
  # the reporting timezone, holding only aggregate counters — deliberately no
  # column can store personal data (no IP, user agent, cookie, or user id), so
  # the table falls outside GDPR scope and needs no consent gate.
  def change do
    create table(:daily_session_metrics) do
      add :date, :date, null: false
      add :session_count, :integer, null: false, default: 0
      add :total_duration_seconds, :bigint, null: false, default: 0

      timestamps()
    end

    create unique_index(:daily_session_metrics, [:date])
  end
end
