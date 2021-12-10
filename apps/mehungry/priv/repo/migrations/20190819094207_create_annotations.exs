defmodule MehungryServer.Repo.Migrations.CreateAnnotations do
  use Ecto.Migration

  def change do
    create table(:annotations) do
      add :body, :text
      add :at, :bigint
      add :user_id, references(:users, on_delete: :nothing)
      add :recipe_id, references(:recipes, on_delete: :nothing)

      timestamps()
    end

    create index(:annotations, [:user_id])
    create index(:annotations, [:recipe_id])
  end
end
