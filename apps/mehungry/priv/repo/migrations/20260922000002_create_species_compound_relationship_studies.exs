defmodule Mehungry.Repo.Migrations.CreateSpeciesCompoundRelationshipStudies do
  use Ecto.Migration

  # Frozen PubMed provenance for a promoted SpeciesCompoundRelationship fact: the
  # co-occurrence reference studies copied off the backing candidate at promotion.
  # Never rewritten by re-derivation. See docs/science/scientific_pipeline.md.
  def change do
    create table(:species_compound_relationship_studies) do
      add :relationship_id,
          references(:species_compound_relationships, on_delete: :delete_all),
          null: false

      add :study_id, references(:scientific_studies, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:species_compound_relationship_studies, [:relationship_id])

    create unique_index(
             :species_compound_relationship_studies,
             [:relationship_id, :study_id],
             name: :species_compound_relationship_studies_natural_key_index
           )
  end
end
