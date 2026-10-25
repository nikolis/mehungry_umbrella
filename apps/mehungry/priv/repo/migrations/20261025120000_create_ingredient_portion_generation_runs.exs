defmodule Mehungry.Repo.Migrations.CreateIngredientPortionGenerationRuns do
  use Ecto.Migration

  # Tracks one "generate derived ingredient portions" batch (one
  # IngredientPortionGenerationWorker job per ingredient) for a live progress
  # bar, mirroring `measurement_unit_reconciliation_runs`. `portions_created`
  # accumulates how many new IngredientPortion rows the sweep synthesized.
  def change do
    create table(:ingredient_portion_generation_runs) do
      add :status, :string, null: false, default: "processing"
      add :total, :integer, null: false, default: 0
      add :completed, :integer, null: false, default: 0
      add :failed, :integer, null: false, default: 0
      add :portions_created, :integer, null: false, default: 0
      add :error, :text
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime

      timestamps()
    end

    create index(:ingredient_portion_generation_runs, [:status])
  end
end
