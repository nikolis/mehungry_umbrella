defmodule Mehungry.Repo.Migrations.CreateCompoundCandidates do
  use Ecto.Migration

  # Two-stage candidate → curated pipeline for ingredient↔compound relationships.
  #
  # `ingredient_compound_candidates` holds *proposed* relationships derived from
  # evidence (PubTator co-occurrence, compound measurements, or manual import),
  # scored and staged (`pending | promoted | rejected`). Promotion writes a curated
  # row into the existing `ingredient_compound_relationships` "facts" table — the
  # candidate table is deliberately separate so unreviewed proposals never
  # masquerade as facts. Mirrors the `ingredient_taxonomy_nodes` candidate/review
  # pattern.
  #
  # `candidate_derivation_runs` tracks a batch derivation pass for a live progress
  # bar, mirroring `ingredient_identity_resolution_runs`.
  def up do
    # ── 1. Derived candidate relationships (staged proposals) ────────────────
    create table(:ingredient_compound_candidates) do
      add :ingredient_id, references(:ingredients, on_delete: :delete_all), null: false
      add :compound_id, references(:compounds, on_delete: :delete_all), null: false

      # What this candidate would promote to (positive-presence only for now).
      add :relationship_type, :string, null: false, default: "contains"
      # Lifecycle: pending → promoted | rejected.
      add :status, :string, null: false, default: "pending"

      # Scored evidence.
      add :evidence_score, :float, null: false, default: 0.0
      add :evidence_level, :string
      # Distinct studies mentioning the compound in a paper linked to the ingredient.
      add :study_count, :integer, null: false, default: 0
      # Distinct studies backing a compound measurement for the pair.
      add :measurement_study_count, :integer, null: false, default: 0
      # Which evidence sources contributed: pubtator | measurement | manual.
      add :sources, {:array, :string}, null: false, default: []
      # Auditable component breakdown (literature/measurement sub-scores, counts).
      add :evidence, :map, null: false, default: %{}
      add :notes, :text

      # The curated fact this candidate promoted into, if any.
      add :promoted_relationship_id,
          references(:ingredient_compound_relationships, on_delete: :nilify_all)

      timestamps()
    end

    # One candidate per (ingredient, compound, relationship_type) — re-derivation upserts.
    # Explicit short name so it isn't truncated (keeps `unique_constraint/2` matching).
    create unique_index(
             :ingredient_compound_candidates,
             [:ingredient_id, :compound_id, :relationship_type],
             name: :ingredient_compound_candidates_natural_key_index
           )

    create index(:ingredient_compound_candidates, [:status])
    create index(:ingredient_compound_candidates, [:compound_id])

    # ── 2. Batch derivation run tracker (progress + PubSub) ──────────────────
    create table(:candidate_derivation_runs) do
      add :status, :string, null: false, default: "pending"
      add :processed, :integer
      add :total, :integer
      add :promoted_count, :integer, null: false, default: 0
      add :error, :text
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime

      timestamps()
    end

    create index(:candidate_derivation_runs, [:status])
  end

  def down do
    drop table(:candidate_derivation_runs)
    drop table(:ingredient_compound_candidates)
  end
end
