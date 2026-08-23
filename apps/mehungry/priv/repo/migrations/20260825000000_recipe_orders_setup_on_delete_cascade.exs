defmodule Mehungry.Repo.Migrations.RecipeOrdersSetupOnDeleteCascade do
  use Ecto.Migration

  # A setup could not be deleted while any order referenced it: the
  # `recipe_orders.recipe_setup_id` FK was `on_delete: :restrict`, so
  # `delete_recipe_setup/1` raised an Ecto.ConstraintError and the admin delete
  # button appeared to do nothing. Orders are throwaway generation batches that
  # belong to a setup, so cascade them when the setup is removed (each order's
  # ai_bot_recipes already nilify their recipe_order_id).
  def change do
    alter table(:ai_bot_recipe_orders) do
      modify :recipe_setup_id,
             references(:ai_bot_recipe_setups, on_delete: :delete_all),
             from: references(:ai_bot_recipe_setups, on_delete: :restrict),
             null: false
    end
  end
end
