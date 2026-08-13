defmodule Mehungry.Repo.Migrations.AddRecipeSetupIdToWeekAndDayConfigs do
  use Ecto.Migration

  def change do
    alter table(:ai_bot_week_configs) do
      add :recipe_setup_id, references(:ai_bot_recipe_setups, on_delete: :nilify_all)
    end

    alter table(:ai_bot_day_configs) do
      add :recipe_setup_id, references(:ai_bot_recipe_setups, on_delete: :nilify_all)
    end

    create index(:ai_bot_week_configs, [:recipe_setup_id])
    create index(:ai_bot_day_configs, [:recipe_setup_id])
  end
end
