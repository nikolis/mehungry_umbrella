defmodule Mehungry.Repo.Migrations.CreateFactMinerSettings do
  use Ecto.Migration

  # UI-managed connection config for the external biomed-fact-miner service
  # (`POST /mine`). A singleton row (the app always reads the first/only row) so an
  # admin can point the miner at a different host and supply a JWT/bearer token from
  # `/professional/health` without a redeploy. Falls back to the
  # `FACT_MINER_BASE_URL` / `FACT_MINER_AUTH_TOKEN` env/config when no row exists.
  def up do
    create table(:fact_miner_settings) do
      add :base_url, :string, null: false
      add :auth_token, :string

      timestamps()
    end
  end

  def down do
    drop table(:fact_miner_settings)
  end
end
