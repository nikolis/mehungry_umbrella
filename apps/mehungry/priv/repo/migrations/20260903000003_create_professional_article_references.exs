defmodule Mehungry.Repo.Migrations.CreateProfessionalArticleReferences do
  use Ecto.Migration

  def change do
    create table(:professional_article_references) do
      add :article_id, references(:professional_articles, on_delete: :delete_all), null: false

      add :paragraph_id,
          references(:professional_article_paragraphs, on_delete: :delete_all),
          null: false

      add :reference_type, :string, null: false

      add :study_id, references(:scientific_studies, on_delete: :delete_all)
      add :species_id, references(:foundemental_food_species, on_delete: :delete_all)
      add :compound_id, references(:compounds, on_delete: :delete_all)
      add :condition_id, references(:conditions, on_delete: :delete_all)

      timestamps()
    end

    create index(:professional_article_references, [:article_id])
    create index(:professional_article_references, [:paragraph_id])

    # Prevent citing the same entity twice from one paragraph. NULLs in the
    # non-matching FK columns are compared as distinct by Postgres, so this only
    # collides real duplicate (paragraph, entity) pairs.
    create unique_index(
             :professional_article_references,
             [:paragraph_id, :reference_type, :study_id, :species_id, :compound_id, :condition_id],
             name: :professional_article_references_unique_target
           )
  end
end
