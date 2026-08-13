defmodule Mehungry.Repo.Migrations.CreateAiBotRecipeOrders do
  use Ecto.Migration

  def change do
    create table(:ai_bot_recipe_orders) do
      add :recipe_setup_id, references(:ai_bot_recipe_setups, on_delete: :restrict), null: false
      add :bot_user_id, references(:users, on_delete: :nilify_all)
      add :quantity, :integer, null: false
      # nil meal_type = cycle across all meal types
      add :meal_type, :string
      add :language_name, :string, null: false, default: "En"
      add :status, :string, null: false, default: "pending"
      add :completed_count, :integer, null: false, default: 0

      timestamps()
    end

    create index(:ai_bot_recipe_orders, [:recipe_setup_id])
    create index(:ai_bot_recipe_orders, [:status])
  end
end
