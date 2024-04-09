defmodule Mehungry.Repo.Migrations.CreateCommentVotes do
  use Ecto.Migration

  def change do
    create table(:comment_votes) do
      add :positive, :boolean, default: false, null: false
      add :comment_id, references(:comments, on_delete: :nothing)
      add :user_id, references(:users, on_delete: :nothing)

      timestamps()
    end

    create index(:comment_votes, [:comment_id])
    create index(:comment_votes, [:user_id])
  end
end
