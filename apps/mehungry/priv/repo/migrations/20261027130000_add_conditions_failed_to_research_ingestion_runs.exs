defmodule Mehungry.Repo.Migrations.AddConditionsFailedToResearchIngestionRuns do
  use Ecto.Migration

  # Fan-out: one job per condition. A condition whose job exhausts its retries is
  # counted here, and the run finalizes when `conditions_done + conditions_failed
  # == conditions_total` (so a few failing conditions can't wedge the run).
  def change do
    alter table(:research_ingestion_runs) do
      add :conditions_failed, :integer, null: false, default: 0
    end
  end
end
