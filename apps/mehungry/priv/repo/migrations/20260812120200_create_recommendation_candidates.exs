defmodule Mehungry.Repo.Migrations.CreateRecommendationCandidates do
  use Ecto.Migration

  # Condition↔compound recommendation candidates derived from `study_entity_relations`
  # (mirrors `species_compound_candidates`). Scored + valence-mapped to a *suggested*
  # direction, review-gated (NEVER auto-promoted), and promoted by an admin into a
  # `Health.CompoundRecommendation` (`source: "literature"`).
  def change do
    create table(:compound_recommendation_candidates) do
      add :condition_id, references(:conditions, on_delete: :delete_all), null: false
      add :compound_id, references(:compounds, on_delete: :delete_all), null: false

      add :suggested_recommendation, :string
      add :status, :string, null: false, default: "pending"
      add :evidence_score, :float, null: false, default: 0.0
      add :evidence_level, :string
      add :relation_counts, :map, default: %{}
      add :study_count, :integer, default: 0
      add :sources, {:array, :string}, default: []
      add :evidence, :map, default: %{}
      add :notes, :string

      add :promoted_recommendation_id,
          references(:compound_recommendations, on_delete: :nilify_all)

      timestamps()
    end

    create unique_index(:compound_recommendation_candidates, [:condition_id, :compound_id],
             name: :compound_recommendation_candidates_natural_key_index
           )

    create index(:compound_recommendation_candidates, [:compound_id])
    create index(:compound_recommendation_candidates, [:condition_id])

    create table(:compound_recommendation_candidate_studies) do
      add :candidate_id,
          references(:compound_recommendation_candidates, on_delete: :delete_all),
          null: false

      add :study_id, references(:scientific_studies, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:compound_recommendation_candidate_studies, [:candidate_id, :study_id])

    # Aggregate progress record for one derivation pass (mirrors
    # candidate_derivation_runs). promoted_count stays 0 — this stage never
    # auto-promotes — but is kept for run-record symmetry.
    create table(:recommendation_derivation_runs) do
      add :status, :string, null: false, default: "pending"
      add :processed, :integer
      add :total, :integer
      add :promoted_count, :integer, default: 0
      add :error, :string
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime

      timestamps()
    end
  end
end
