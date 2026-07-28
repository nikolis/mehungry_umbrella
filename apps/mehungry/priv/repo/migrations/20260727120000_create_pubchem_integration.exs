defmodule Mehungry.Repo.Migrations.CreatePubchemIntegration do
  use Ecto.Migration

  # PubChem integration layer for the `Mehungry.Chemistry` context.
  #
  # PubChem is treated as an external authority (like USDA for ingredients): the
  # importer normalizes a fuzzy name into a stable chemical identity and syncs it
  # into the canonical `compounds` registry. These two tables are the sidecar:
  #
  #   * `pubchem_responses`  — append-only cache of every raw PUG REST payload,
  #     so the original response is never lost (reproducibility, re-import,
  #     resilience against PubChem schema changes).
  #   * `compound_sources`   — per-source provenance for a compound, so PubChem is
  #     not hard-coded as the only authority (FooDB/ChEBI/HMDB slot in later).
  #
  # The existing `compounds` table is NOT altered.
  def up do
    # ── 1. Raw API cache (append-only history) ───────────────────────────────
    create table(:pubchem_responses) do
      # Which PUG REST endpoint produced this payload.
      add :endpoint, :string, null: false
      # The input name, for name→CID lookups (nil for cid-keyed fetches).
      add :requested_name, :string
      # The resolved/queried CID (nil for a name lookup that matched nothing).
      add :cid, :integer
      add :raw_json, :map, null: false
      add :etag, :string
      add :api_version, :string
      add :retrieved_at, :utc_datetime, null: false

      timestamps()
    end

    create index(:pubchem_responses, [:cid])
    create index(:pubchem_responses, [:endpoint, :requested_name])

    # ── 2. Per-source provenance layer ───────────────────────────────────────
    create table(:compound_sources) do
      add :compound_id, references(:compounds, on_delete: :delete_all), null: false
      add :source_type, :string, null: false
      add :external_identifier, :string, null: false
      add :last_synced_at, :utc_datetime
      # The raw payload this sync was built from.
      add :raw_response_id, references(:pubchem_responses, on_delete: :nilify_all)

      timestamps()
    end

    # One row per (compound, source) — makes re-sync an idempotent upsert.
    create unique_index(:compound_sources, [:compound_id, :source_type])
    create index(:compound_sources, [:raw_response_id])
  end

  def down do
    drop table(:compound_sources)
    drop table(:pubchem_responses)
  end
end
