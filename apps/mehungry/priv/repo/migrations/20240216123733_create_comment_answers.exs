defmodule Mehungry.Repo.Migrations.CreateCommentAnswers do
  use Ecto.Migration

  def change do
    create table(:comment_answers) do
      add :text, :string
      add :user_id, references(:users, on_delete: :nothing)
      add :comment_id, references(:comments, on_delete: :nothing)

      timestamps()
    end

    create index(:comment_answers, [:user_id])
    create index(:comment_answers, [:comment_id])
  end
end
