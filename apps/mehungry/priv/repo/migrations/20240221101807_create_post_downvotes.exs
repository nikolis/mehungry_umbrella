defmodule Mehungry.Repo.Migrations.CreatePostDownvotes do
  use Ecto.Migration

  def change do
    create table(:post_downvotes) do
      add :post_id, references(:posts, on_delete: :nothing)
      add :user_id, references(:users, on_delete: :nothing)

      timestamps()
    end

    create index(:post_downvotes, [:post_id])
    create index(:post_downvotes, [:user_id])
  end
end
