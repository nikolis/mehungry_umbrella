defmodule Mehungry.Repo.Migrations.CreatePosts do
  use Ecto.Migration

  def change do
    create table(:posts) do
      add :type_, :string
      add :reference_id, :integer
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

    create index(:posts, [:user_id])
    create index(:posts, [:recipe_id])
  end
end
