defmodule Mehungry.Repo.Migrations.CreateStudyConditionExclusions do
  use Ecto.Migration

  # A persistent "this paper does NOT belong to this condition" flag, set when an
  # admin re-assigns a discovered paper to a better-fitting condition on
  # `/professional/health`. The reverse (condition-seeded) crawl consults it so a
  # re-crawl of the origin condition never re-links the paper it was moved away from.
  #
  # Keyed on `(study, condition)` — unlike `study_conditions` it is term-agnostic:
  # once a paper is flagged for a condition, no search term under that condition may
  # re-link it.
  def up do
    create table(:study_condition_exclusions) do
      add :study_id, references(:scientific_studies, on_delete: :delete_all), null: false
      add :condition_id, references(:conditions, on_delete: :delete_all), null: false
      # Where the paper was re-assigned to (provenance; nullable — the row is a flag
      # first, a move-record second).
      add :reassigned_to_condition_id, references(:conditions, on_delete: :nilify_all)

      timestamps()
    end

    create unique_index(:study_condition_exclusions, [:study_id, :condition_id])
    create index(:study_condition_exclusions, [:condition_id])
  end

  def down do
    drop table(:study_condition_exclusions)
  end
end
