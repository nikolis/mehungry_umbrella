defmodule Mehungry.Repo.Migrations.CreateHashtagReconciliations do
  use Ecto.Migration

  # Durable per-recipe tracking for the admin hashtag-reconciliation sweep. One
  # row per recipe; `status` walks pending -> processing -> completed | failed so
  # the reconciliation LiveView can show progress and re-run only the undone
  # recipes. Mirrors seed_files, but keyed on recipe_id (the unit of work).
  def change do
    create table(:hashtag_reconciliations) do
      add :recipe_id, references(:recipes, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "pending"
      add :tags_added, :integer
      add :error, :text
      add :completed_at, :utc_datetime

      timestamps()
    end

    create unique_index(:hashtag_reconciliations, [:recipe_id])
  end
end
