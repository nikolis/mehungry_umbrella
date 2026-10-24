defmodule Mehungry.Repo.Migrations.CreateGutenbergImports do
  use Ecto.Migration

  # Durable per-recipe tracking for the admin Project Gutenberg recipe-import
  # review. One row per recipe `ref` ("<book_id>:<index>", e.g. "6385:12"), so
  # the review LiveView can resume across sessions and per book. Mirrors
  # myplate_imports, keyed on the ref (the unit of work). `recipe_id` points at
  # the created recipe (nilified if that recipe is later deleted).
  def change do
    create table(:gutenberg_imports) do
      add :ref, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :recipe_id, references(:recipes, on_delete: :nilify_all)
      add :unmatched_count, :integer
      add :error, :text
      add :completed_at, :utc_datetime

      timestamps()
    end

    create unique_index(:gutenberg_imports, [:ref])
  end
end
