defmodule Mehungry.Repo.Migrations.CreateConditionStateRecommendations do
  use Ecto.Migration

  # The DECOUPLED phase-aware advice store — deliberately separate from
  # `compound_recommendations` / `nutrient_recommendations` so phase-specific advice
  # never leaks into the shared read surfaces (/foods filter, recipe badges, blueprint
  # auto-suggest) until the "combine" step wires it in. Surfaced only on the condition
  # page's phase selector. A row with `condition_state_id = nil` is general/all-phase.
  def up do
    create table(:condition_state_recommendations) do
      add :condition_id, references(:conditions, on_delete: :delete_all), null: false
      add :condition_state_id, references(:condition_states, on_delete: :delete_all)

      # Target: a registry compound, a nutrient (canonical name), or a food pattern.
      add :compound_id, references(:compounds, on_delete: :nilify_all)
      add :nutrient_name, :string
      add :raw_food_term, :string

      add :recommendation, :string, null: false
      add :severity, :string
      add :evidence_level, :string
      add :source, :string, null: false
      add :notes, :text
      add :source_reference, :map

      # Deterministic idempotency key (nullable target/state columns — see the
      # candidate table's dedup_key rationale).
      add :dedup_key, :string, null: false

      timestamps()
    end

    create unique_index(:condition_state_recommendations, [:dedup_key])
    create index(:condition_state_recommendations, [:condition_id])
    create index(:condition_state_recommendations, [:condition_state_id])

    # Frozen PubMed provenance — copied once at promotion, never touched by
    # re-extraction (mirrors compound_recommendation_studies).
    create table(:condition_state_recommendation_studies) do
      add :recommendation_id,
          references(:condition_state_recommendations, on_delete: :delete_all),
          null: false

      add :study_id, references(:scientific_studies, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(
             :condition_state_recommendation_studies,
             [:recommendation_id, :study_id],
             name: :condition_state_recommendation_studies_natural_key_index
           )

    # Back-reference from the candidate to its promoted recommendation (the FK was
    # deferred here since this table is created in this migration).
    alter table(:condition_recommendation_candidates) do
      add :promoted_recommendation_id,
          references(:condition_state_recommendations, on_delete: :nilify_all)
    end
  end

  def down do
    alter table(:condition_recommendation_candidates) do
      remove :promoted_recommendation_id
    end

    drop table(:condition_state_recommendation_studies)
    drop table(:condition_state_recommendations)
  end
end
