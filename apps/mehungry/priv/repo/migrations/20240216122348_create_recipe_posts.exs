defmodule Mehungry.Repo.Migrations.CreateRecipePosts do
  use Ecto.Migration

  def change do
    create table(:recipe_posts) do
      add :title, :string
      add :reference_url, :string
      add :sm_media_url, :string
      add :md_media_url, :string
      add :bg_media_url, :string
      add :description, :string
      add :user_id, references(:users, on_delete: :nothing)
      add :recipe_id, references(:recipes, on_delete: :nothing)

      timestamps()
    end

    create index(:recipe_posts, [:user_id])
    create index(:recipe_posts, [:recipe_id])
  end
end
