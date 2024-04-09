defmodule Mehungry.Repo.Migrations.EditAdditionsRecipeUserMealsTable do
  use Ecto.Migration

  def change do
    alter table(:history_recipe_user_meals) do
      add :consume_portions, :integer
      add :cooking, :boolean
      add :cooking_portions, :integer
    end
  end
end
