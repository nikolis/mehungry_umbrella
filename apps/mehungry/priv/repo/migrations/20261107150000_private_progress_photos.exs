defmodule Mehungry.Repo.Migrations.PrivateProgressPhotos do
  use Ecto.Migration

  def change do
    alter table(:progress_photos) do
      # `url` is now only a legacy carrier (pre-private-bucket rows, cleared by
      # `mix progress.migrate_photos`); private-bucket photos store only
      # `storage_key` and are served via short-lived signed URLs.
      modify :url, :string, null: true, from: {:string, null: false}

      # Opt-in public sharing: a crypto-random token behind
      # GET /shared/photos/:token. NULL = not shared (revocable).
      add :share_token, :string
      add :shared_at, :utc_datetime
    end

    create unique_index(:progress_photos, [:share_token])
  end
end
