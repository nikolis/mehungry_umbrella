defmodule Mehungry.Repo.Migrations.CreateUnitoolsImports do
  use Ecto.Migration

  # Durable per-recipe tracking for the admin UniTools recipe-import review. One
  # row per recipe `ref` ("<dataset_id>:<index>", e.g. "v1:12"), so the review
  # LiveView can resume across sessions and per dataset. Mirrors
  # gutenberg_imports, keyed on the ref (the unit of work). `recipe_id` points at
  # the created recipe (nilified if that recipe is later deleted).
  def change do
    create table(:unitools_imports) do
      add :ref, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :recipe_id, references(:recipes, on_delete: :nilify_all)
      add :unmatched_count, :integer
      add :error, :text
      add :completed_at, :utc_datetime

      timestamps()
    end

    create unique_index(:unitools_imports, [:ref])
  end
end
