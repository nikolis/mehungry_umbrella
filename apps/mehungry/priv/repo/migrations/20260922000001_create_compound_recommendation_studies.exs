defmodule Mehungry.Repo.Migrations.CreateCompoundRecommendationStudies do
  use Ecto.Migration

  # Frozen PubMed provenance for a promoted CompoundRecommendation: the reference
  # studies copied off the backing candidate at promotion time. Unlike the candidate
  # study links, these are never rewritten by re-derivation — they cite what the
  # human actually validated. See docs/science/scientific_pipeline.md.
  def change do
    create table(:compound_recommendation_studies) do
      add :recommendation_id,
          references(:compound_recommendations, on_delete: :delete_all),
          null: false

      add :study_id, references(:scientific_studies, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:compound_recommendation_studies, [:recommendation_id])

    create unique_index(
             :compound_recommendation_studies,
             [:recommendation_id, :study_id],
             name: :compound_recommendation_studies_natural_key_index
           )
  end
end
