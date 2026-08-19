defmodule Mehungry.Repo.Migrations.CreateAiBotRecipeSetupIngredients do
  use Ecto.Migration

  def change do
    create table(:ai_bot_recipe_setup_ingredients) do
      add :recipe_setup_id, references(:ai_bot_recipe_setups, on_delete: :delete_all), null: false
      add :ingredient_id, references(:ingredients, on_delete: :delete_all), null: false
      # primary | garnish | spice | avoid
      add :role, :string, null: false

      timestamps()
    end

    create index(:ai_bot_recipe_setup_ingredients, [:recipe_setup_id])
    create index(:ai_bot_recipe_setup_ingredients, [:ingredient_id])

    create unique_index(:ai_bot_recipe_setup_ingredients, [
             :recipe_setup_id,
             :ingredient_id,
             :role
           ])
  end
end
