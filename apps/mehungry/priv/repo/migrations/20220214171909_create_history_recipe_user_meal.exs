defmodule MehungryApi.Repo.Migrations.CreateHistoryRecipeUserMeal do
  use Ecto.Migration

  def change do
    create table(:history_recipe_user_meals) do
      add :recipe_id, references(:recipes, on_delete: :delete_all)
      add :user_meal_id, references(:history_user_meals, on_delete: :delete_all)
      add :consume_portions, :integer
      add :cooking, :boolean
      add :cooking_portions, :integer

    end

    create index(:history_recipe_user_meals, [:recipe_id])
    create index(:history_recipe_user_meals, [:user_meal_id])
  end
end
