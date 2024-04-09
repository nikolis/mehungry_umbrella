defmodule Mehungry.Repo.Migrations.AddUserRecipeTable do
  use Ecto.Migration

  def change do
    create table(:user_recipes) do
      add :recipe_id, references(:recipes, on_delete: :delete_all)
      add :user_id, references(:users, on_delete: :delete_all)

      timestamps()
    end

    create index(:user_recipes, [:recipe_id])
    create index(:user_recipes, [:user_id])
  end
end
