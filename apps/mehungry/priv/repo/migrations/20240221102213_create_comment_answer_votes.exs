defmodule Mehungry.Repo.Migrations.CreateCommentAnswerVotes do
  use Ecto.Migration

  def change do
    create table(:comment_answer_votes) do
      add :positive, :boolean, default: false, null: false
      add :comment_answer_id, references(:comment_answers, on_delete: :nothing)
      add :user_id, references(:users, on_delete: :nothing)

      timestamps()
    end

    create index(:comment_answer_votes, [:comment_answer_id])
    create index(:comment_answer_votes, [:user_id])
  end
end
