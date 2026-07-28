defmodule Mehungry.Repo.Migrations.CreateIngredientEnrichmentTables do
  use Ecto.Migration

  # Decoupled scientific-enrichment sidecar. Keyed by ingredient_id, never
  # read or written by FoodData.Usda.FoodParser / IngredientReconciliationWorker,
  # so enrichment survives every USDA re-import and reconciliation pass. In
  # particular, enrichment is kept OUT of ingredient_nutrients / ingredient_portions,
  # which reconciliation delete-then-recreates.
  def up do
    # Citation registry — the shared provenance layer. One citation row can back
    # many enrichment facts across the three fact tables below.
    create table(:ingredient_enrichment_sources) do
      add :title, :string
      add :source_type, :string, null: false
      add :identifier, :string
      add :url, :string
      add :retrieved_at, :utc_datetime

      timestamps()
    end

    create unique_index(:ingredient_enrichment_sources, [:source_type, :identifier])

    # Bioactive / compound measures (glycemic index, ORAC, total polyphenols…).
    # Deliberately separate from ingredient_nutrients (which reconciliation wipes).
    create table(:ingredient_scientific_properties) do
      add :ingredient_id, references(:ingredients, on_delete: :delete_all), null: false

      add :enrichment_source_id,
          references(:ingredient_enrichment_sources, on_delete: :nilify_all)

      add :property_key, :string, null: false
      add :value, :float
      add :unit, :string
      add :basis, :string
      add :source, :string, null: false
      add :confidence, :float
      add :reviewed, :boolean, default: false, null: false
      add :retrieved_at, :utc_datetime

      timestamps()
    end

    create unique_index(:ingredient_scientific_properties, [
             :ingredient_id,
             :property_key,
             :source
           ])

    create index(:ingredient_scientific_properties, [:enrichment_source_id])

    # Scientific classification — per-ingredient binomial / species naming.
    create table(:ingredient_classifications) do
      add :ingredient_id, references(:ingredients, on_delete: :delete_all), null: false

      add :enrichment_source_id,
          references(:ingredient_enrichment_sources, on_delete: :nilify_all)

      add :scientific_name, :string, null: false
      add :genus, :string
      add :species, :string
      add :cultivar, :string
      add :rank, :string
      add :external_ref, :string
      add :source, :string, null: false
      add :confidence, :float
      add :reviewed, :boolean, default: false, null: false
      add :retrieved_at, :utc_datetime

      timestamps()
    end

    create unique_index(:ingredient_classifications, [:ingredient_id, :scientific_name])
    create index(:ingredient_classifications, [:enrichment_source_id])

    # Health / dietary attributes — namespaced flags (allergen:gluten, fodmap:high…).
    create table(:ingredient_health_attributes) do
      add :ingredient_id, references(:ingredients, on_delete: :delete_all), null: false

      add :enrichment_source_id,
          references(:ingredient_enrichment_sources, on_delete: :nilify_all)

      add :attribute, :string, null: false
      add :value, :string
      add :source, :string, null: false
      add :confidence, :float
      add :reviewed, :boolean, default: false, null: false
      add :retrieved_at, :utc_datetime

      timestamps()
    end

    create unique_index(:ingredient_health_attributes, [:ingredient_id, :attribute, :source])
    create index(:ingredient_health_attributes, [:enrichment_source_id])
  end

  def down do
    drop table(:ingredient_scientific_properties)
    drop table(:ingredient_classifications)
    drop table(:ingredient_health_attributes)
    drop table(:ingredient_enrichment_sources)
  end
end
