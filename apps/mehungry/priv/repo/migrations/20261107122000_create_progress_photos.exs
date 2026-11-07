defmodule Mehungry.Repo.Migrations.CreateProgressPhotos do
  use Ecto.Migration

  def change do
    create table(:progress_photos) do
      add :progress_entry_id, references(:progress_entries, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :url, :string, null: false
      add :storage_key, :string
      add :position, :integer, null: false, default: 0
      add :caption, :string

      timestamps()
    end

    create index(:progress_photos, [:progress_entry_id])
    create index(:progress_photos, [:user_id])
  end
end
