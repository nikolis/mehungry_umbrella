defmodule Mehungry.Repo.Migrations.CreatePubtatorAnnotations do
  use Ecto.Migration

  # NCBI PubTator3 entity-extraction layer for the `Mehungry.Literature` context.
  #
  # PubTator3 is treated as an external authority — like USDA for ingredients,
  # PubChem for compounds, and Entrez for papers: it analyses a discovered
  # `ScientificStudy` and returns the entities mentioned in it (Chemicals,
  # Species, Diseases). Each mention is recorded as a first-class
  # `study_entity_mention` — an extracted fact only. No relationship is inferred
  # (a mention never writes an `ingredient_compound_relationship`); the original
  # surface text and the source are preserved.
  #
  # No existing table is altered. These tables are keyed by their own ids /
  # `study_id` / `compound_id` and are never read or written by the USDA ingestion
  # path.
  def up do
    # ── 1. Extracted entity mentions (the facts) ─────────────────────────────
    create table(:study_entity_mentions) do
      add :study_id, references(:scientific_studies, on_delete: :delete_all), null: false
      # chemical | species | disease
      add :entity_type, :string, null: false
      # Namespaced normalized id: "mesh:D000082" (chemical/disease),
      # "ncbitaxon:9606" (species). Nil when PubTator left the mention unnormalized.
      add :normalized_identifier, :string
      # The preserved original surface text of the mention.
      add :text_span, :string, null: false
      # Character offset of the mention, distinguishing repeated mentions.
      add :offset, :integer
      add :confidence, :float
      add :source, :string, null: false, default: "pubtator3"
      # Identity link for a resolved chemical (normalization, not a dietary fact).
      add :compound_id, references(:compounds, on_delete: :nilify_all)

      timestamps()
    end

    # One row per distinct mention location; re-annotating a study upserts.
    # Explicit name — the default would exceed Postgres's 63-char identifier limit.
    create unique_index(
             :study_entity_mentions,
             [:study_id, :entity_type, :normalized_identifier, :offset],
             name: :study_entity_mentions_natural_key_index
           )

    create index(:study_entity_mentions, [:study_id])
    create index(:study_entity_mentions, [:compound_id])

    # ── 2. Raw PubTator API cache (append-only history) ──────────────────────
    create table(:pubtator_responses) do
      add :endpoint, :string, null: false
      add :pmid, :integer
      add :raw_json, :map, null: false
      add :retrieved_at, :utc_datetime, null: false

      timestamps()
    end

    create index(:pubtator_responses, [:pmid])

    # ── 3. Per-study dedup ledger (guarantees the batch terminates) ──────────
    create table(:pubtator_annotation_attempts) do
      add :study_id, references(:scientific_studies, on_delete: :delete_all), null: false
      # annotated | no_results | error
      add :outcome, :string, null: false
      add :mentions_found, :integer, default: 0
      add :last_annotated_at, :utc_datetime

      timestamps()
    end

    create unique_index(:pubtator_annotation_attempts, [:study_id])

    # ── 4. Aggregate run progress ────────────────────────────────────────────
    create table(:pubtator_annotation_runs) do
      add :status, :string, default: "pending", null: false
      add :processed, :integer
      add :total, :integer
      add :mentions_found, :integer
      add :error, :text
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime

      timestamps()
    end
  end

  def down do
    drop table(:pubtator_annotation_runs)
    drop table(:pubtator_annotation_attempts)
    drop table(:pubtator_responses)
    drop table(:study_entity_mentions)
  end
end
