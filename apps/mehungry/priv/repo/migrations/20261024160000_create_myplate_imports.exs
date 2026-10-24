defmodule Mehungry.Repo.Migrations.CreateMyplateImports do
  use Ecto.Migration

  # Durable per-slug tracking for the admin MyPlate recipe-import sweep. One row
  # per MyPlate recipe slug; `status` walks pending -> processing -> completed |
  # failed so the import LiveView can show progress and re-run only the undone
  # slugs. Mirrors hashtag_reconciliations, keyed on the slug (the unit of work).
  # `recipe_id` points at the created recipe (nilified if that recipe is later
  # deleted); `unmatched_count` records how many ingredient lines couldn't be
  # matched to existing DB entries.
  def change do
    create table(:myplate_imports) do
      add :slug, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :recipe_id, references(:recipes, on_delete: :nilify_all)
      add :unmatched_count, :integer
      add :error, :text
      add :completed_at, :utc_datetime

      timestamps()
    end

    create unique_index(:myplate_imports, [:slug])
  end
end
