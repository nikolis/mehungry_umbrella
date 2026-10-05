defmodule Mehungry.Repo.Migrations.CreateStudyAnalyses do
  use Ecto.Migration

  # The persisted, per-paper result of the `mehungry_extractor` batch-PMID
  # `/analyze` service (see `mehungry_extractor/docs/api.md`). One row per
  # `ScientificStudy` (the paper is the natural key): its extracted `claims`
  # (the normalized concept layer the endpoint returns) + study/funding facts +
  # batch-context fields from the run that produced them. Re-running "Analyze
  # selected" reconciles against this table — a `content_hash` mismatch triggers
  # an in-place update.
  #
  # Extracted claims only — a stored analysis never asserts a dietary fact
  # (that stays in the `Food.*` / `Health` layers).
  def up do
    create table(:study_analyses) do
      add :study_id, references(:scientific_studies, on_delete: :delete_all), null: false

      add :status, :string, null: false
      add :error, :text

      add :paper_title, :text
      add :publication_year, :integer
      add :source_type, :string
      add :study_design, :string
      add :sample_size, :integer
      add :funder_types, {:array, :string}, null: false, default: []
      add :funding_independence, :string
      add :n_claims, :integer
      add :concept_count, :integer
      add :cohesion_score, :float

      # jsonb holding the paper's `claims_list` (a JSON array) — loaded as
      # `{:array, :map}` in the schema; always set by the changeset.
      add :claims, :map
      add :run, :map, null: false, default: %{}
      add :content_hash, :string, null: false
      add :analyzed_at, :utc_datetime

      timestamps()
    end

    # One analysis per paper; re-analysis upserts this row.
    create unique_index(:study_analyses, [:study_id])
  end

  def down do
    drop table(:study_analyses)
  end
end
