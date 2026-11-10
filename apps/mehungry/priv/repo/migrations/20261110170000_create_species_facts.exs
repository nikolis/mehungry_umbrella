defmodule Mehungry.Repo.Migrations.CreateSpeciesFacts do
  use Ecto.Migration

  # Species enrichment facts (see docs/implementation/science/species_enrichment.md).
  #
  # Provenance-cited "interesting info" attached to a `FoundementalFoodSpecies` and
  # surfaced in the /foods "Origins & cultivation" section: where a food originates
  # (Wikidata, CC0), where it's grown (FAOSTAT top producers, CC BY 4.0), a short
  # description + Wikipedia link. Every fact lands **review-gated** (`reviewed: false`)
  # because external identity-matching (e.g. a Wikidata top-hit) can mismatch; an admin
  # promotes at /professional/species-enrichment. Provenance reuses the shared
  # `ingredient_enrichment_sources` citation registry.
  def up do
    # Curated crosswalk from a species to its FAOSTAT crop/livestock item code. Nullable:
    # many species (processed, variety-level, non-FAO) have no FAOSTAT item.
    alter table(:foundemental_food_species) do
      add :faostat_item_code, :string
    end

    create table(:species_facts) do
      add :foundemental_species_id,
          references(:foundemental_food_species, on_delete: :delete_all),
          null: false

      # The per-fact citation (a Wikidata entity URL / the FAOSTAT dataset), shared
      # across facts via the generic enrichment-source registry.
      add :enrichment_source_id,
          references(:ingredient_enrichment_sources, on_delete: :nilify_all)

      # origin_region | description | wikipedia_url | top_producers
      add :fact_key, :string, null: false
      # Human-readable value (origin region text, Wikipedia URL, description prose).
      add :value_text, :text
      # Structured value (top-producers list) when the fact isn't a single string.
      add :value_json, :map
      # "en" / "el" for locale-specific facts (description, wikipedia_url); "" for
      # locale-independent facts (origin_region, top_producers). NOT NULL with a ""
      # default so the natural-key unique index dedups on re-fetch — Postgres treats
      # NULLs as distinct, which would let locale-independent facts duplicate.
      add :locale, :string, null: false, default: ""

      add :source, :string, null: false, default: "external_db"
      add :confidence, :float
      # pending → promoted | rejected. Only `promoted` facts surface; `rejected` is
      # sticky so a re-fetch (which upserts only extraction fields, never status)
      # doesn't resurrect a fact an admin already dismissed.
      add :status, :string, null: false, default: "pending"
      add :retrieved_at, :utc_datetime

      timestamps()
    end

    # One fact per (species, key, locale, source) — re-fetch upserts on this key.
    create unique_index(
             :species_facts,
             [:foundemental_species_id, :fact_key, :locale, :source],
             name: :species_facts_natural_key_index
           )

    create index(:species_facts, [:status])
    create index(:species_facts, [:foundemental_species_id])
  end

  def down do
    drop table(:species_facts)

    alter table(:foundemental_food_species) do
      remove :faostat_item_code
    end
  end
end
