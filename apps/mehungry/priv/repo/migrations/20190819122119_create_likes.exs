defmodule MehungryServer.Repo.Migrations.CreateLikes do
  use Ecto.Migration

  def change do
    create table(:likes) do
      add :at, :bigint
      add :user_id, references(:users, on_delete: :nothing)
      add :recipe_id, references(:recipes, on_delete: :nothing)

      timestamps()
    end

    create index(:likes, [:user_id])
    create index(:likes, [:recipe_id])
  end
end
