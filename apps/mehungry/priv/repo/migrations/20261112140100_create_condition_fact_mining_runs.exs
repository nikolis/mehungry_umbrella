defmodule Mehungry.Repo.Migrations.CreateConditionFactMiningRuns do
  use Ecto.Migration

  # Per-condition tracking rows for a "Mine all conditions" fan-out: one row per
  # condition per batch, grouped by `batch_id`. Each `ConditionFactMiningWorker`
  # job advances its own row (pending → processing → completed | failed) and
  # records how many facts it stored. The admin LiveView streams these rows (O(1)
  # patches) and derives aggregate progress by counting over the current
  # `batch_id`. The condition-scope twin of `species_fact_mining_runs`.
  def change do
    create table(:condition_fact_mining_runs) do
      add :batch_id, :string, null: false
      add :condition_id, references(:conditions, on_delete: :delete_all), null: false

      add :status, :string, null: false, default: "pending"
      add :facts_total, :integer, null: false, default: 0
      add :verified_count, :integer, null: false, default: 0
      add :contradicted_count, :integer, null: false, default: 0
      add :error, :text
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime

      timestamps()
    end

    create index(:condition_fact_mining_runs, [:batch_id])
    create index(:condition_fact_mining_runs, [:status])

    create unique_index(:condition_fact_mining_runs, [:batch_id, :condition_id],
             name: :condition_fact_mining_runs_batch_condition_index
           )
  end
end
