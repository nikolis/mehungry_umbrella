defmodule Mehungry.Repo.Migrations.CreateAiBotRecipes do
  use Ecto.Migration

  def change do
    create table(:ai_bot_recipes) do
      add :recipe_id, references(:recipes, on_delete: :restrict), null: false
      add :bot_config_id, references(:ai_bot_configs, on_delete: :restrict), null: false
      add :meal_type, :string, null: false
      add :scheduled_date, :date, null: false
      add :status, :string, null: false, default: "pending_review"

      timestamps()
    end

    create index(:ai_bot_recipes, [:bot_config_id])
    create index(:ai_bot_recipes, [:scheduled_date, :status])
    create index(:ai_bot_recipes, [:recipe_id])
    create unique_index(:ai_bot_recipes, [:bot_config_id, :meal_type, :scheduled_date])
  end
end
