defmodule Mehungry.Repo.Migrations.CreateFoodCompounds do
  use Ecto.Migration

  # Food Compound Knowledge layer. Represents bioactive / chemical compounds
  # (oxalates, lectins, phytates, histamine, polyphenols, FODMAP compounds,
  # purines, salicylates, other bioactives) as first-class reference entities,
  # and links them to ingredients as scientific facts (e.g. "Spinach contains
  # Oxalate"). Facts only — no recommendations or dietary advice are stored here.
  #
  # `compounds` is a shared registry (like `nutrients`); the join is keyed by
  # ingredient_id and never read or written by the USDA ingestion/reconciliation
  # path, so it survives every re-import.
  def up do
    # ── 1. Compound registry (shared reference entities) ─────────────────────
    create table(:compounds) do
      add :name, :string, null: false
      add :compound_type, :string, null: false
      add :pubchem_cid, :integer
      add :chebi_id, :string
      add :synonyms, {:array, :string}, default: [], null: false
      add :identifiers, :map, default: %{}, null: false
      add :description, :text

      timestamps()
    end

    create unique_index(:compounds, [:name])

    create unique_index(:compounds, [:pubchem_cid], where: "pubchem_cid IS NOT NULL")

    create index(:compounds, [:compound_type])

    # ── 2. Ingredient ↔ compound relationships (scientific facts) ────────────
    create table(:ingredient_compound_relationships) do
      add :ingredient_id, references(:ingredients, on_delete: :delete_all), null: false
      add :compound_id, references(:compounds, on_delete: :delete_all), null: false

      # Optional citation into the shared enrichment provenance registry.
      add :enrichment_source_id,
          references(:ingredient_enrichment_sources, on_delete: :nilify_all)

      add :relationship_type, :string, null: false, default: "contains"
      add :confidence, :float
      add :source, :string, null: false
      add :notes, :text

      timestamps()
    end

    # Never-overwrite natural key: the same fact from the same source is deduped,
    # but a different source or relationship type is kept as its own row.
    create unique_index(:ingredient_compound_relationships, [
             :ingredient_id,
             :compound_id,
             :relationship_type,
             :source
           ])

    create index(:ingredient_compound_relationships, [:compound_id])
    create index(:ingredient_compound_relationships, [:enrichment_source_id])
  end

  def down do
    drop table(:ingredient_compound_relationships)
    drop table(:compounds)
  end
end
