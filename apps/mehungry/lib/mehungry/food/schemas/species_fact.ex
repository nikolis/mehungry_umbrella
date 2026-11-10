defmodule Mehungry.Food.SpeciesFact do
  @moduledoc """
  A provenance-cited enrichment fact attached directly to a `FoundementalFoodSpecies`
  — the "interesting info" surfaced in the /foods "Origins & cultivation" section:
  where a food comes from (Wikidata, CC0), where it's grown (FAOSTAT top producers,
  CC BY 4.0), a short description, a Wikipedia link.

  Staged `pending → promoted | rejected`: external identity-matching can mismatch (a
  Wikidata top-hit for an ambiguous name), so a fact only surfaces once an admin promotes
  it at `/professional/species-enrichment`. `rejected` is sticky — a re-fetch upserts only
  extraction fields, never `status`, so a dismissed fact doesn't resurface. Provenance is
  the shared `enrichment_source` citation registry (`IngredientEnrichmentSource`).

  `locale` is `"en"`/`"el"` for locale-specific facts (description, wikipedia_url) and
  `""` for locale-independent ones (origin_region, top_producers) — see the migration
  for why `""` rather than `nil`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Food.{FoundementalFoodSpecies, IngredientEnrichmentSource}

  @fact_keys ~w(origin_region description wikipedia_url top_producers)
  @sources ~w(external_db manual ai)
  @statuses ~w(pending promoted rejected)

  schema "species_facts" do
    field :fact_key, :string
    field :value_text, :string
    field :value_json, :map
    field :locale, :string, default: ""
    field :source, :string, default: "external_db"
    field :confidence, :float
    field :status, :string, default: "pending"
    field :retrieved_at, :utc_datetime

    belongs_to :species, FoundementalFoodSpecies, foreign_key: :foundemental_species_id
    belongs_to :enrichment_source, IngredientEnrichmentSource

    timestamps()
  end

  @castable ~w(foundemental_species_id enrichment_source_id fact_key value_text value_json
               locale source confidence status retrieved_at)a

  def changeset(fact, attrs) do
    fact
    |> cast(attrs, @castable)
    |> update_change(:locale, &(&1 || ""))
    |> validate_required([:foundemental_species_id, :fact_key, :source, :status])
    |> validate_inclusion(:fact_key, @fact_keys)
    |> validate_inclusion(:source, @sources)
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:foundemental_species_id)
    |> unique_constraint([:foundemental_species_id, :fact_key, :locale, :source],
      name: :species_facts_natural_key_index
    )
  end

  @doc "The valid `fact_key` values."
  def fact_keys, do: @fact_keys
end
