defmodule Mehungry.Repo.Migrations.CreateConditionRecommendationCandidates do
  use Ecto.Migration

  # Phase-aware, review-gated recommendation candidates extracted from condition
  # literature by the offline Python service. Unlike `compound_recommendation_candidates`
  # (derived from state-blind PubTator relations), each row here is tagged with a
  # `condition_state` (nullable = general/all-phase) and can target a compound, a
  # nutrient (by canonical name), or a free-text food pattern (e.g. "low-residue").
  # Never auto-promoted — an admin confirms direction + severity + state.
  def up do
    create table(:condition_recommendation_candidates) do
      add :condition_id, references(:conditions, on_delete: :delete_all), null: false
      add :condition_state_id, references(:condition_states, on_delete: :nilify_all)
      add :compound_id, references(:compounds, on_delete: :nilify_all)
      add :nutrient_name, :string
      add :raw_term, :string, null: false
      add :target_kind, :string, null: false

      add :suggested_recommendation, :string
      add :suggested_severity, :string
      add :status, :string, null: false, default: "pending"
      add :evidence_score, :float, default: 0.0
      add :confidence, :float
      add :evidence_level, :string
      add :study_count, :integer, default: 0
      add :evidence, :map, default: %{}
      add :extraction_method, :string, default: "llm_fulltext"
      add :notes, :text

      # `promoted_recommendation_id` FK → condition_state_recommendations is added by
      # the Part E migration (that table is created there).

      # Deterministic idempotency key — the natural key spans nullable columns
      # (state/compound/nutrient), which Postgres would treat as distinct under a plain
      # composite unique index, so the app computes a single stable string instead.
      add :dedup_key, :string, null: false

      timestamps()
    end

    create unique_index(:condition_recommendation_candidates, [:dedup_key])
    create index(:condition_recommendation_candidates, [:condition_id])
    create index(:condition_recommendation_candidates, [:status])

    # Provenance: which studies backed a candidate (additive — each extraction POST
    # links its study). Frozen copies are made into
    # `condition_state_recommendation_studies` at promotion.
    create table(:condition_recommendation_candidate_studies) do
      add :candidate_id,
          references(:condition_recommendation_candidates, on_delete: :delete_all),
          null: false

      add :study_id, references(:scientific_studies, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(
             :condition_recommendation_candidate_studies,
             [:candidate_id, :study_id],
             name: :condition_rec_candidate_studies_natural_key_index
           )

    # Termination ledger for the extraction pipeline: a (study, condition) pair leaves
    # the `condition_pending` set once the Python service posts back, exactly like
    # `pmc_fetch_attempts` gates `list_unfetched_studies`.
    create table(:condition_rec_extraction_attempts) do
      add :study_id, references(:scientific_studies, on_delete: :delete_all), null: false
      add :condition_id, references(:conditions, on_delete: :delete_all), null: false
      add :candidates_found, :integer, default: 0

      timestamps()
    end

    create unique_index(:condition_rec_extraction_attempts, [:study_id, :condition_id])
  end

  def down do
    drop table(:condition_rec_extraction_attempts)
    drop table(:condition_recommendation_candidate_studies)
    drop table(:condition_recommendation_candidates)
  end
end
