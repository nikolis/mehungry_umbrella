defmodule Mehungry.Repo.Migrations.CreateRatings do
  use Ecto.Migration

  def change do
    create table(:ratings) do
      add :stars, :integer
      add :user_id, references(:users, on_delete: :nothing)
      add :recipe_id, references(:recipes, on_delete: :nothing)

      timestamps()
    end

    create index(:ratings, [:user_id])
    create index(:ratings, [:recipe_id])

    create unique_index(:ratings, [:user_id, :recipe_id], name: :index_ratings_on_user_recipe)
  end
end
