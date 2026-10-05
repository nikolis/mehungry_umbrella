defmodule Mehungry.Repo.Migrations.CreateExtractorSettings do
  use Ecto.Migration

  # UI-managed connection config for the batch paper-analysis service
  # (`mehungry_extractor`, `POST /analyze`). A singleton row (the app always reads
  # the first/only row) so an admin can point the analyzer at a different host and
  # supply an auth token without a redeploy. Falls back to the `EXTRACTOR_BASE_URL`
  # env/config when no row exists.
  def up do
    create table(:extractor_settings) do
      add :base_url, :string, null: false
      add :auth_token, :string

      timestamps()
    end
  end

  def down do
    drop table(:extractor_settings)
  end
end
