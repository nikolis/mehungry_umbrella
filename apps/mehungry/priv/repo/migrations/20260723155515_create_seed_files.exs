defmodule Mehungry.Repo.Migrations.CreateSeedFiles do
  use Ecto.Migration

  # Durable per-file tracking for the S3 ingredient-seeding flow. One row per
  # (bucket, key); `status` walks pending -> processing -> completed | failed so
  # the S3 browser can show progress and re-enqueue only the undone files. Unlike
  # the transient oban_jobs record (pruned after completion), this survives to
  # drive the "re-do undone" list across restarts.
  def change do
    create table(:seed_files) do
      add :bucket, :string, null: false
      add :key, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :ingredient_count, :integer
      add :error, :text
      add :completed_at, :utc_datetime

      timestamps()
    end

    create unique_index(:seed_files, [:bucket, :key])
  end
end
