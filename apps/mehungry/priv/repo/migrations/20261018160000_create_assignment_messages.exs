defmodule Mehungry.Repo.Migrations.CreateAssignmentMessages do
  use Ecto.Migration

  def change do
    create table(:assignment_messages) do
      add :professional_id, references(:users, on_delete: :delete_all), null: false
      add :client_id, references(:users, on_delete: :delete_all), null: false
      add :sender_user_id, references(:users, on_delete: :delete_all), null: false
      add :body, :text, null: false
      add :read_at, :utc_datetime

      timestamps()
    end

    # Thread load (one conversation per professional↔client pair).
    create index(:assignment_messages, [:professional_id, :client_id])
    # Unread counts, per recipient side.
    create index(:assignment_messages, [:client_id, :read_at])
    create index(:assignment_messages, [:professional_id, :read_at])
  end
end
