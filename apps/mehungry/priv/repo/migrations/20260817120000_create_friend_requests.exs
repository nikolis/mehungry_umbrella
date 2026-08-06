defmodule Mehungry.Repo.Migrations.CreateFriendRequests do
  use Ecto.Migration

  def change do
    create table(:friend_requests) do
      add :requester_id, references(:users, on_delete: :delete_all), null: false
      add :recipient_id, references(:users, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "pending"
      add :message, :text

      timestamps()
    end

    create unique_index(:friend_requests, [:requester_id, :recipient_id])
    create index(:friend_requests, [:recipient_id])
    create index(:friend_requests, [:status])
  end
end
