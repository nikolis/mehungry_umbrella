defmodule Mehungry.Repo.Migrations.CreateUserDevices do
  use Ecto.Migration

  def change do
    create table(:user_devices) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :expo_token, :string, null: false
      add :platform, :string, null: false
      add :last_seen_at, :utc_datetime

      timestamps()
    end

    # A given device (Expo token) belongs to exactly one user at a time — a
    # re-registration under another user moves it (upsert on this target).
    create unique_index(:user_devices, [:expo_token])
    create index(:user_devices, [:user_id])
  end
end
