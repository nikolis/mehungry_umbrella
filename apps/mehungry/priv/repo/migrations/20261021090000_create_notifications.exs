defmodule Mehungry.Repo.Migrations.CreateNotifications do
  use Ecto.Migration

  def change do
    create table(:notifications) do
      add :recipient_id, references(:users, on_delete: :delete_all), null: false
      add :actor_id, references(:users, on_delete: :nilify_all)
      add :type, :string, null: false
      add :subject_type, :string
      add :subject_id, :bigint
      add :data, :map, null: false, default: %{}
      add :read_at, :utc_datetime

      timestamps()
    end

    # Inbox: newest-first per recipient.
    create index(:notifications, [:recipient_id, :inserted_at])
    # Unread badge: cheap count of just the unread rows.
    create index(:notifications, [:recipient_id], where: "read_at IS NULL", name: :notifications_unread_index)
  end
end
