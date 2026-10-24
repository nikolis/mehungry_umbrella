defmodule Mehungry.Repo.Migrations.CreateAppSettings do
  use Ecto.Migration

  # Tiny shared key-value store for runtime-tunable, admin-settable app settings
  # that must survive deploys and be consistent across all running machines
  # (DB is the only correct home for that — Application.put_env is per-node and
  # resets on restart). First consumer: the recipe-image provider toggle.
  def change do
    create table(:app_settings) do
      add :key, :string, null: false
      add :value, :string

      timestamps()
    end

    create unique_index(:app_settings, [:key])
  end
end
