defmodule Mehungry.Repo.Migrations.CreateRecipeTimeEstimation do
  use Ecto.Migration

  # AI backfill of missing recipe prep/cook times (the meal planner's ≤15 / ≤40 min
  # rules exclude a recipe with no time). `times_estimated_at` stamps every recipe the
  # estimator attempted, so a run can never loop on one the model skipped; the run
  # table tracks one admin "Estimate missing times" click (Oban-UI-connected pattern).
  def change do
    alter table(:recipes) do
      add :times_estimated_at, :utc_datetime
    end

    create table(:recipe_time_estimation_runs) do
      add :status, :string, null: false, default: "pending"
      add :processed, :integer, null: false, default: 0
      add :total, :integer, null: false, default: 0
      add :error, :text
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime

      timestamps()
    end
  end
end
