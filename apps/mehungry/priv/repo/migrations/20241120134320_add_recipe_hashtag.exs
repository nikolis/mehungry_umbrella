defmodule Mehungry.Repo.Migrations.AddRecipeHashtag do
  use Ecto.Migration

  def change do
    create table(:recipe_hashtags) do
      add :recipe_id, references(:recipes, on_delete: :delete_all)
      add :hashtag_id, references(:hashtags, on_delete: :delete_all)
    end

    create index(:recipe_hashtags, [:hashtag_id])
    create index(:recipe_hashtags, [:recipe_id])
  end
end
