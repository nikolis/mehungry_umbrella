defmodule Mehungry.Repo.Migrations.CreateGlycemicIndexTables do
  use Ecto.Migration

  # Path-B Glycemic Index pipeline (see docs/science/glycemic_index_licensing.md).
  #
  # GI values are **re-derived from primary literature**, not ingested from the
  # copyrighted International Tables. The pipeline mirrors the compound-measurement
  # extraction flow: the Entrez crawl discovers GI feeding-trial studies (species ×
  # "glycemic index" keyword), the non-deployed local-AI service extracts the measured
  # GI value from each paper's full text, and each finding is fanned over the
  # `FoundementalFoodSpecies` the study links to as a **review-gated**
  # `glycemic_index_candidate` (`pending → promoted | rejected`). Promotion writes the
  # value onto every ingredient of the species as an `IngredientScientificProperty`
  # (`property_key: "glycemic_index"`, `basis: "glucose=100"`), recording the ids so an
  # Undo removes exactly those. Provenance is the primary study — there is no table
  # ingest, no `quality_tier`, and no name-match layer (species come from discovery).
  def up do
    create table(:glycemic_index_candidates) do
      # Provenance: the primary study the value was extracted from.
      add :study_id, references(:scientific_studies, on_delete: :delete_all), null: false

      # Fan-out target; the ingredient fallback covers one-off direct matches.
      add :foundemental_species_id,
          references(:foundemental_food_species, on_delete: :delete_all)

      add :ingredient_id, references(:ingredients, on_delete: :nilify_all)

      # The extracted measurement + the paper metadata that grades its quality.
      add :gi_value, :float, null: false
      add :gi_sem, :float
      add :reference_food, :string
      add :sample_size, :integer
      add :country, :string
      add :year, :integer
      add :analytical_method, :string
      # True when the paper reports an ISO 26642:2010-consistent method — the signal
      # that (with an exact species link) makes a candidate auto-promotable.
      add :iso_method, :boolean, null: false, default: false

      # Extraction bookkeeping (mirrors compound_measurement_candidates).
      add :score, :float
      add :raw_span, :text
      add :extraction_method, :string, null: false, default: "automated"

      add :status, :string, null: false, default: "pending"
      # IngredientScientificProperty ids written on promotion — enables Undo.
      add :promoted_property_ids, {:array, :integer}, null: false, default: []

      # The per-study citation shared by every property this candidate promotes into.
      add :enrichment_source_id,
          references(:ingredient_enrichment_sources, on_delete: :nilify_all)

      timestamps()
    end

    # One candidate per (study, species, value) — re-extraction upserts on this key.
    create unique_index(
             :glycemic_index_candidates,
             [:study_id, :foundemental_species_id, :gi_value],
             name: :glycemic_index_candidates_natural_key_index
           )

    create index(:glycemic_index_candidates, [:status])
    create index(:glycemic_index_candidates, [:foundemental_species_id])
    create index(:glycemic_index_candidates, [:study_id])
  end

  def down do
    drop table(:glycemic_index_candidates)
  end
end
