defmodule Mehungry.Repo.Migrations.CreateFeedbacks do
  use Ecto.Migration

  def change do
    create table(:feedbacks) do
      add :message, :text, null: false
      add :email, :string
      add :user_id, references(:users, on_delete: :nilify_all)

      timestamps(updated_at: false)
    end

    create index(:feedbacks, [:user_id])
  end
end
