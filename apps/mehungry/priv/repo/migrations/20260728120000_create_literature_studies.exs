defmodule Mehungry.Repo.Migrations.CreateLiteratureStudies do
  use Ecto.Migration

  # Scientific-literature discovery layer for the `Mehungry.Literature` context.
  #
  # NCBI Entrez (PubMed) is treated as an external authority — exactly like USDA
  # for ingredients and PubChem for compounds: a crawler searches an ingredient's
  # scientific name combined with compound/phytochemistry terms, and records the
  # resulting papers as first-class `scientific_studies` linked back to both the
  # ingredient and (when the search term matches the registry) the compound.
  #
  # No existing table is altered. These tables are keyed by their own ids /
  # `ingredient_id` / `compound_id` and are never read or written by the USDA
  # ingestion / reconciliation path.
  def up do
    # ── 1. Paper registry (deduped by PMID) ──────────────────────────────────
    create table(:scientific_studies) do
      # PubMed identifier — the natural dedup key.
      add :pmid, :integer, null: false
      add :doi, :string
      add :title, :string
      add :abstract, :text
      add :journal, :string
      # PubMed publication dates are irregular (year-only, "1998 Mar", …), so we
      # store the raw string exactly like `ingredients.publication_date`.
      add :publication_date, :string
      add :authors, {:array, :string}, default: []
      # Extra efetch fields (MeSH, volume, …) kept without widening the table.
      add :raw_metadata, :map
      add :retrieved_at, :utc_datetime

      timestamps()
    end

    create unique_index(:scientific_studies, [:pmid])
    create index(:scientific_studies, [:doi])

    # ── 2. Study ↔ ingredient facts (with search-term provenance) ────────────
    create table(:study_ingredients) do
      add :study_id, references(:scientific_studies, on_delete: :delete_all), null: false
      add :ingredient_id, references(:ingredients, on_delete: :delete_all), null: false
      # The exact query that surfaced this paper, e.g. "Spinacia oleracea oxalate".
      add :search_term, :string, null: false
      # Snapshot of the scientific name used, for audit.
      add :scientific_name, :string
      add :source, :string, default: "pubmed"

      timestamps()
    end

    create unique_index(:study_ingredients, [:study_id, :ingredient_id, :search_term])
    create index(:study_ingredients, [:ingredient_id])

    # ── 3. Study ↔ compound facts ────────────────────────────────────────────
    create table(:study_compounds) do
      add :study_id, references(:scientific_studies, on_delete: :delete_all), null: false
      add :compound_id, references(:compounds, on_delete: :delete_all), null: false
      add :search_term, :string

      timestamps()
    end

    create unique_index(:study_compounds, [:study_id, :compound_id])
    create index(:study_compounds, [:compound_id])

    # ── 4. Raw Entrez API cache (append-only history) ────────────────────────
    create table(:entrez_responses) do
      # Which E-utilities endpoint produced this payload.
      add :endpoint, :string, null: false
      # The search term, for esearch lookups (nil for id-keyed fetches).
      add :query, :string
      # A resolved/queried PMID (nil for a search that returned a list).
      add :pmid, :integer
      # efetch XML is decoded to a map before storage so the cache stays queryable.
      add :raw_json, :map, null: false
      add :retrieved_at, :utc_datetime, null: false

      timestamps()
    end

    create index(:entrez_responses, [:endpoint, :query])
    create index(:entrez_responses, [:pmid])

    # ── 5. Per-(ingredient, term) dedup ledger (guarantees termination) ──────
    create table(:literature_crawl_attempts) do
      add :ingredient_id, references(:ingredients, on_delete: :delete_all), null: false
      add :search_term, :string, null: false
      add :outcome, :string, null: false
      add :studies_found, :integer, default: 0
      add :last_crawled_at, :utc_datetime

      timestamps()
    end

    # One row per (ingredient, term) — upsertable; excludes already-crawled pairs
    # from the next batch, so the crawl always terminates.
    create unique_index(:literature_crawl_attempts, [:ingredient_id, :search_term])

    # ── 6. Aggregate run progress ────────────────────────────────────────────
    create table(:literature_crawl_runs) do
      add :status, :string, default: "pending", null: false
      add :processed, :integer
      add :total, :integer
      add :studies_found, :integer
      add :error, :text
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime

      timestamps()
    end
  end

  def down do
    drop table(:literature_crawl_runs)
    drop table(:literature_crawl_attempts)
    drop table(:entrez_responses)
    drop table(:study_compounds)
    drop table(:study_ingredients)
    drop table(:scientific_studies)
  end
end
