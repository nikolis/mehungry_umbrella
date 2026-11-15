defmodule Mehungry.Repo.Migrations.BackfillCancelledFactMiningRuns do
  use Ecto.Migration

  # Admin cancels used to be modeled as `status: "failed", error: "cancelled by
  # admin"`. They now have their own neutral `"cancelled"` status — convert the
  # existing rows so they stop rendering as red failures.
  def up do
    execute(
      "UPDATE species_fact_mining_runs SET status = 'cancelled', error = NULL WHERE error = 'cancelled by admin'"
    )

    execute(
      "UPDATE condition_fact_mining_runs SET status = 'cancelled', error = NULL WHERE error = 'cancelled by admin'"
    )
  end

  def down do
    execute(
      "UPDATE species_fact_mining_runs SET status = 'failed', error = 'cancelled by admin' WHERE status = 'cancelled'"
    )

    execute(
      "UPDATE condition_fact_mining_runs SET status = 'failed', error = 'cancelled by admin' WHERE status = 'cancelled'"
    )
  end
end
