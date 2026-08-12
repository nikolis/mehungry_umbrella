defmodule Mehungry.Repo.Migrations.CreateNutrientRecalculationRuns do
  use Ecto.Migration

  # Batch progress tracker for the "recompute all recipe nutrients" admin action,
  # mirroring `candidate_derivation_runs`. One row per bulk run carries a
  # completed/failed/total counter refreshed as each RecipePutNutrientsWorker job
  # finishes, transitions processing → completed, and broadcasts every change on
  # `Mehungry.PubSub` so the Recipes admin view can render a live progress bar.
  def change do
    create table(:nutrient_recalculation_runs) do
      add :status, :string, null: false, default: "processing"
      add :total, :integer, null: false, default: 0
      add :completed, :integer, null: false, default: 0
      add :failed, :integer, null: false, default: 0
      add :error, :text
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime

      timestamps()
    end

    create index(:nutrient_recalculation_runs, [:status])
  end
end
