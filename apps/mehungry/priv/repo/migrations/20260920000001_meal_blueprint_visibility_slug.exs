defmodule Mehungry.Repo.Migrations.MealBlueprintVisibilitySlug do
  use Ecto.Migration

  def change do
    alter table(:meal_blueprints) do
      # "private" (default) or "public" — public blueprints are browsable and
      # shareable via their slug; private ones are owner-only.
      add :visibility, :string, null: false, default: "private"
      # URL slug for the public preview page (/blueprints/:slug). Generated from
      # the name on insert and kept stable across edits.
      add :slug, :string
    end

    create unique_index(:meal_blueprints, [:slug])
    create index(:meal_blueprints, [:visibility])
  end
end
