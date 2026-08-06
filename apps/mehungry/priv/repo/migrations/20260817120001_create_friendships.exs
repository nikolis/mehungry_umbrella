defmodule Mehungry.Repo.Migrations.CreateFriendships do
  use Ecto.Migration

  def change do
    create table(:friendships) do
      add :user_low_id, references(:users, on_delete: :delete_all), null: false
      add :user_high_id, references(:users, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:friendships, [:user_low_id, :user_high_id])
    create index(:friendships, [:user_high_id])
  end
end
