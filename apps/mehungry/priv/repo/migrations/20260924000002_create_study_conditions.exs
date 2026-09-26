defmodule Mehungry.Repo.Migrations.CreateStudyConditions do
  use Ecto.Migration

  # A discovered link between a `ScientificStudy` and a `Health.Condition`, produced by
  # the reverse (condition-seeded) literature crawl — the condition analogue of
  # `study_ingredients`. It carries the `search_term` that surfaced the paper so the
  # condition page can show "Research on this condition" and the extraction pipeline
  # knows which condition a study was crawled for.
  #
  # A cross-context FK to `conditions` (owned by `Mehungry.Health`), mirroring the
  # existing `study_compounds → compounds` precedent — the schemas stay decoupled.
  def up do
    create table(:study_conditions) do
      add :study_id, references(:scientific_studies, on_delete: :delete_all), null: false
      add :condition_id, references(:conditions, on_delete: :delete_all), null: false
      add :search_term, :string, null: false
      add :source, :string, null: false, default: "pubmed"

      timestamps()
    end

    # One row per (study, condition, term) — the same paper can be re-found under
    # several terms without duplication.
    create unique_index(:study_conditions, [:study_id, :condition_id, :search_term])
    create index(:study_conditions, [:condition_id])
  end

  def down do
    drop table(:study_conditions)
  end
end
