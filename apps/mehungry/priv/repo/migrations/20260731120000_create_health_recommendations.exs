defmodule Mehungry.Repo.Migrations.CreateHealthRecommendations do
  use Ecto.Migration

  # Health Recommendation Knowledge layer (`Mehungry.Health`). Represents health
  # conditions (Kidney Stones, IBS, Gout, …) as first-class reference entities and
  # links them to bioactive compounds as *recommendations* — e.g. "Kidney Stones:
  # avoid Oxalate", "IBS: limit FODMAP".
  #
  # The hard rule: a condition NEVER references an ingredient. It references a
  # compound. "Which foods should a kidney-stone patient avoid?" is derived by
  # composing this layer with `ingredient_compound_relationships` at read time —
  # the schemas stay decoupled. This is the advice layer the "facts only"
  # compound docs (docs/science/food_compounds.md §4) defer to.
  def up do
    # ── 1. Condition registry (shared reference entities) ────────────────────
    create table(:conditions) do
      add :name, :string, null: false
      add :synonyms, {:array, :string}, default: [], null: false
      add :category, :string
      add :description, :text

      timestamps()
    end

    create unique_index(:conditions, [:name])
    create index(:conditions, [:category])

    # ── 2. Condition ↔ compound recommendations (dietary advice) ─────────────
    create table(:compound_recommendations) do
      add :condition_id, references(:conditions, on_delete: :delete_all), null: false
      add :compound_id, references(:compounds, on_delete: :delete_all), null: false

      add :recommendation, :string, null: false
      add :severity, :string
      add :evidence_level, :string
      add :source, :string, null: false
      add :notes, :text

      timestamps()
    end

    # Never-overwrite natural key: one recommendation per condition/compound per
    # source; re-asserting from the same source upserts, a different source is a
    # distinct row.
    create unique_index(:compound_recommendations, [:condition_id, :compound_id, :source])

    create index(:compound_recommendations, [:compound_id])
    create index(:compound_recommendations, [:condition_id])
  end

  def down do
    drop table(:compound_recommendations)
    drop table(:conditions)
  end
end
