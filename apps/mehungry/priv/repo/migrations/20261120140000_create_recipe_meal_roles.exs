defmodule Mehungry.Repo.Migrations.CreateRecipeMealRoles do
  use Ecto.Migration

  # Meal roles (main / side / meze / breakfast …) per recipe — multi-label, see
  # `Mehungry.Food.MealRoles`. `recipes.meal_roles_classified_at` marks a recipe
  # the classifier has attempted (even when it returned nothing), so a backfill
  # run always moves forward. `recipe_meal_role_runs` tracks admin-triggered
  # classification runs for the live progress bar.
  def change do
    create table(:recipe_meal_roles) do
      add :recipe_id, references(:recipes, on_delete: :delete_all), null: false
      add :role, :string, null: false
      add :source, :string, null: false
      add :confidence, :float
      add :reviewed, :boolean, default: false, null: false
      add :reviewed_by_id, references(:users, on_delete: :nilify_all)
      add :reviewed_at, :utc_datetime

      timestamps()
    end

    create unique_index(:recipe_meal_roles, [:recipe_id, :role])
    create index(:recipe_meal_roles, [:role])
    create index(:recipe_meal_roles, [:reviewed, :confidence])

    alter table(:recipes) do
      add :meal_roles_classified_at, :utc_datetime
    end

    create table(:recipe_meal_role_runs) do
      add :mode, :string, null: false, default: "unclassified"
      add :status, :string, null: false, default: "pending"
      add :processed, :integer, default: 0, null: false
      add :total, :integer, default: 0, null: false
      add :error, :text
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime

      timestamps()
    end
  end
end
