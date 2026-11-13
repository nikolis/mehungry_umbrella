defmodule Mehungry.Repo.Migrations.DropSpeciesCompoundPipeline do
  use Ecto.Migration

  # The species↔compound derivation pipeline (`Mehungry.CompoundPipeline`) and its
  # curated-fact output were retired, replaced by the per-species biomed-fact-miner
  # pipeline (`Mehungry.FactMining` → `species_mined_facts`). Drop the candidate,
  # run, relationship, and provenance tables in child→parent order.
  #
  # Irreversible in practice (the data is gone); `down` recreates bare table shells
  # so a rollback leaves the schema consistent even though the rows are not restored.
  def up do
    drop_if_exists table(:species_compound_candidate_studies)
    drop_if_exists table(:species_compound_candidates)
    drop_if_exists table(:candidate_derivation_runs)
    drop_if_exists table(:species_compound_relationship_studies)
    drop_if_exists table(:species_compound_relationships)
  end

  def down do
    create table(:species_compound_relationships) do
      add :foundemental_species_id,
          references(:foundemental_food_species, on_delete: :delete_all)

      add :compound_id, references(:compounds, on_delete: :delete_all)
      add :relationship_type, :string
      add :confidence, :float
      add :source, :string
      add :notes, :text
      timestamps()
    end

    create table(:species_compound_relationship_studies) do
      add :relationship_id,
          references(:species_compound_relationships, on_delete: :delete_all)

      add :study_id, references(:scientific_studies, on_delete: :delete_all)
      timestamps()
    end

    create table(:candidate_derivation_runs) do
      add :status, :string
      add :processed, :integer
      add :total, :integer
      add :promoted_count, :integer
      add :error, :text
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime
      timestamps()
    end

    create table(:species_compound_candidates) do
      add :foundemental_species_id,
          references(:foundemental_food_species, on_delete: :delete_all)

      add :compound_id, references(:compounds, on_delete: :delete_all)
      add :relationship_type, :string
      add :status, :string
      add :evidence_score, :float
      add :evidence_level, :string
      add :study_count, :integer
      add :measurement_study_count, :integer
      add :sources, {:array, :string}
      add :evidence, :map
      add :plausibility_verdict, :string
      add :plausibility_reason, :text
      add :plausibility_checked_at, :utc_datetime

      add :promoted_relationship_id,
          references(:species_compound_relationships, on_delete: :nilify_all)

      timestamps()
    end

    create table(:species_compound_candidate_studies) do
      add :candidate_id, references(:species_compound_candidates, on_delete: :delete_all)
      add :study_id, references(:scientific_studies, on_delete: :delete_all)
      timestamps()
    end
  end
end
