defmodule Mehungry.Repo.Migrations.AddRecipeOrderIdToAiBotRecipes do
  use Ecto.Migration

  def change do
    alter table(:ai_bot_recipes) do
      add :recipe_order_id, references(:ai_bot_recipe_orders, on_delete: :nilify_all)
    end

    # Order-generated recipes have no calendar config; the changeset enforces
    # that one of bot_config_id / recipe_order_id is present. NULL bot_config_id
    # rows are treated as distinct by the existing unique index, so ordering
    # many recipes never collides on it.
    alter table(:ai_bot_recipes) do
      modify :bot_config_id, :bigint, null: true, from: {:bigint, null: false}
    end

    create index(:ai_bot_recipes, [:recipe_order_id])
  end
end
