defmodule Mehungry.Repo.Migrations.CreatePostUpvotes do
  use Ecto.Migration

  def change do
    create table(:post_upvotes) do
      add :post_id, references(:posts, on_delete: :nothing)
      add :user_id, references(:users, on_delete: :nothing)

      timestamps()
    end

    create index(:post_upvotes, [:post_id])
    create index(:post_upvotes, [:user_id])
  end
end
