defmodule Mehungry.Repo.Migrations.CreateIngredientScientificIdentities do
  use Ecto.Migration

  # Scientific Identity Resolution layer. Maps existing (USDA-backed) ingredients
  # to external scientific identifiers — scientific name, NCBI taxonomy id, FoodOn
  # id, Wikidata id, synonyms — as candidate mappings with confidence + provenance
  # and a manual verification lifecycle. Fully decoupled: keyed by ingredient_id,
  # never read or written by the USDA ingestion/reconciliation path. Append-only
  # (never overwrites), so historical mappings are preserved.
  def up do
    # ── 1. Candidate scientific identities (append-only history) ─────────────
    create table(:ingredient_scientific_identities) do
      add :ingredient_id, references(:ingredients, on_delete: :delete_all), null: false

      # Optional citation into the enrichment provenance registry (reused).
      add :enrichment_source_id,
          references(:ingredient_enrichment_sources, on_delete: :nilify_all)

      add :scientific_name, :string, null: false
      add :rank, :string
      add :ncbi_taxonomy_id, :integer
      add :foodon_id, :string
      add :wikidata_id, :string

      # Provenance: where the scientific_name came from, and (separately) where the
      # external identifiers came from.
      add :source, :string, null: false
      add :id_source, :string

      add :confidence, :float
      add :status, :string, null: false, default: "candidate"

      # Manual verification workflow.
      add :verified_by_user_id, references(:users, on_delete: :nilify_all)
      add :verified_at, :utc_datetime

      # History chain: when a verified identity is replaced, the old row is marked
      # `superseded` and points at the row that replaced it (never deleted).
      add :superseded_by_id,
          references(:ingredient_scientific_identities, on_delete: :nilify_all)

      add :notes, :text

      timestamps()
    end

    create index(:ingredient_scientific_identities, [:ingredient_id])
    create index(:ingredient_scientific_identities, [:ingredient_id, :status])
    create index(:ingredient_scientific_identities, [:ncbi_taxonomy_id])
    create index(:ingredient_scientific_identities, [:enrichment_source_id])

    # Never-overwrite: an identical candidate from the same source is deduped, so
    # re-resolution is a find-or-create, not an update.
    create unique_index(:ingredient_scientific_identities, [
             :ingredient_id,
             :scientific_name,
             :source
           ])

    # At most one VERIFIED identity per ingredient (the verification workflow
    # supersedes the previous one first, inside a transaction).
    create unique_index(:ingredient_scientific_identities, [:ingredient_id],
             where: "status = 'verified'",
             name: :one_verified_identity_per_ingredient
           )

    # ── 2. Synonyms, per scientific identity ─────────────────────────────────
    create table(:ingredient_identity_synonyms) do
      add :scientific_identity_id,
          references(:ingredient_scientific_identities, on_delete: :delete_all),
          null: false

      add :name, :string, null: false
      add :synonym_type, :string
      # Plain string, no FK to languages — keeps the enrichment layer decoupled.
      add :language_name, :string
      add :source, :string

      timestamps()
    end

    create unique_index(:ingredient_identity_synonyms, [
             :scientific_identity_id,
             :name,
             :synonym_type
           ])

    # ── 3. Per-ingredient resolution attempt ledger (like seed_files) ────────
    # Records that an ingredient was processed — even when USDA has no
    # scientificName — so the batch worker terminates and each item is audited.
    create table(:ingredient_identity_resolution_attempts) do
      add :ingredient_id, references(:ingredients, on_delete: :delete_all), null: false
      add :source, :string, null: false
      add :outcome, :string, null: false
      add :detail, :text
      add :attempted_at, :utc_datetime

      timestamps()
    end

    create unique_index(:ingredient_identity_resolution_attempts, [:ingredient_id, :source])

    # ── 4. Aggregate progress runs (like taxonomy_classification_runs) ───────
    create table(:ingredient_identity_resolution_runs) do
      add :status, :string, null: false, default: "pending"
      add :resolved, :integer
      add :total, :integer
      add :error, :text
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime

      timestamps()
    end

    create index(:ingredient_identity_resolution_runs, [:status])
  end

  def down do
    drop table(:ingredient_identity_resolution_runs)
    drop table(:ingredient_identity_resolution_attempts)
    drop table(:ingredient_identity_synonyms)
    drop table(:ingredient_scientific_identities)
  end
end
