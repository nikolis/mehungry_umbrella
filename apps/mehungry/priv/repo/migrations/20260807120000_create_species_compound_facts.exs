defmodule Mehungry.Repo.Migrations.CreateSpeciesCompoundFacts do
  use Ecto.Migration

  @moduledoc """
  Re-keys the candidate/fact layer of stage 4 (candidate derivation) from ingredient
  to `FoundementalFoodSpecies`:

    * `species_compound_relationships` — the curated species↔compound facts.
    * `species_compound_candidates` — the scored, reviewable suggestions.
    * `species_compound_candidate_studies` — the reference-study provenance per candidate.

  The old `ingredient_compound_candidates` is dropped (rebuildable by re-deriving). The
  ingredient-level `ingredient_compound_relationships` table is left intact (dormant
  manual/AI API).
  """

  def up do
    create table(:species_compound_relationships) do
      add :foundemental_species_id,
          references(:foundemental_food_species, on_delete: :delete_all),
          null: false

      add :compound_id, references(:compounds, on_delete: :delete_all), null: false
      add :relationship_type, :string, null: false, default: "contains"
      add :confidence, :float
      add :source, :string
      add :notes, :text

      timestamps()
    end

    create index(:species_compound_relationships, [:compound_id])

    create unique_index(
             :species_compound_relationships,
             [:foundemental_species_id, :compound_id, :relationship_type, :source],
             name: :species_compound_relationships_natural_key_index
           )

    create table(:species_compound_candidates) do
      add :foundemental_species_id,
          references(:foundemental_food_species, on_delete: :delete_all),
          null: false

      add :compound_id, references(:compounds, on_delete: :delete_all), null: false
      add :relationship_type, :string, null: false, default: "contains"
      add :status, :string, null: false, default: "pending"
      add :evidence_score, :float, null: false, default: 0.0
      add :evidence_level, :string
      add :study_count, :integer, null: false, default: 0
      add :measurement_study_count, :integer, null: false, default: 0
      add :sources, {:array, :string}, null: false, default: []
      add :evidence, :map, null: false, default: %{}
      add :notes, :text

      add :promoted_relationship_id,
          references(:species_compound_relationships, on_delete: :nilify_all)

      timestamps()
    end

    create index(:species_compound_candidates, [:compound_id])

    create unique_index(
             :species_compound_candidates,
             [:foundemental_species_id, :compound_id, :relationship_type],
             name: :species_compound_candidates_natural_key_index
           )

    create table(:species_compound_candidate_studies) do
      add :candidate_id, references(:species_compound_candidates, on_delete: :delete_all),
        null: false

      add :study_id, references(:scientific_studies, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:species_compound_candidate_studies, [:study_id])
    create unique_index(:species_compound_candidate_studies, [:candidate_id, :study_id])

    drop table(:ingredient_compound_candidates)
  end

  def down do
    # Recreate the ingredient-keyed candidate table (as it was before this migration).
    create table(:ingredient_compound_candidates) do
      add :ingredient_id, references(:ingredients, on_delete: :delete_all), null: false
      add :compound_id, references(:compounds, on_delete: :delete_all), null: false
      add :relationship_type, :string, null: false, default: "contains"
      add :status, :string, null: false, default: "pending"
      add :evidence_score, :float, null: false, default: 0.0
      add :evidence_level, :string
      add :study_count, :integer, null: false, default: 0
      add :measurement_study_count, :integer, null: false, default: 0
      add :sources, {:array, :string}, null: false, default: []
      add :evidence, :map, null: false, default: %{}
      add :notes, :text

      add :promoted_relationship_id,
          references(:ingredient_compound_relationships, on_delete: :nilify_all)

      timestamps()
    end

    create unique_index(
             :ingredient_compound_candidates,
             [:ingredient_id, :compound_id, :relationship_type],
             name: :ingredient_compound_candidates_natural_key_index
           )

    drop table(:species_compound_candidate_studies)
    drop table(:species_compound_candidates)
    drop table(:species_compound_relationships)
  end
end
