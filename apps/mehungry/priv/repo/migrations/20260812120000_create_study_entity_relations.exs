defmodule Mehungry.Repo.Migrations.CreateStudyEntityRelations do
  use Ecto.Migration

  # PubTator3's per-document `relations` array — the directional signal
  # (Negative_Correlation / Positive_Correlation / Association / Cotreatment)
  # between two entities. Already downloaded into `pubtator_responses.raw_json`
  # but previously discarded; now structured so a chemical↔disease relation can
  # feed condition recommendations.
  #
  # Both entity endpoints keep their raw namespaced identifier (audit/provenance)
  # AND resolve to our structured registries where possible: chemical → compounds,
  # disease → conditions. Either FK may be nil (unresolvable / non-dietary / a
  # gene endpoint we don't model).
  def change do
    create table(:study_entity_relations) do
      add :study_id, references(:scientific_studies, on_delete: :delete_all), null: false

      add :type, :string, null: false
      add :score, :float

      add :entity1_type, :string
      add :entity1_identifier, :string
      add :entity1_name, :string
      add :entity2_type, :string
      add :entity2_identifier, :string
      add :entity2_name, :string

      add :compound_id, references(:compounds, on_delete: :nilify_all)
      add :condition_id, references(:conditions, on_delete: :nilify_all)

      add :source, :string, null: false, default: "pubtator3"

      timestamps()
    end

    create unique_index(
             :study_entity_relations,
             [:study_id, :type, :entity1_identifier, :entity2_identifier],
             name: :study_entity_relations_natural_key_index
           )

    create index(:study_entity_relations, [:compound_id])
    create index(:study_entity_relations, [:condition_id])
  end
end
