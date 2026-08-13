defmodule Mehungry.Repo.Migrations.AddRecipeSetupIdToAiBotConfigs do
  use Ecto.Migration

  def change do
    alter table(:ai_bot_configs) do
      add :recipe_setup_id, references(:ai_bot_recipe_setups, on_delete: :nilify_all)
    end

    create index(:ai_bot_configs, [:recipe_setup_id])
  end
end
