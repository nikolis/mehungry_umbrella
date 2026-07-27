defmodule Mehungry.Food.IngredientScientificIdentity do
  @moduledoc """
  A candidate scientific identity for an ingredient — the core of the Identity
  Resolution layer.

  Maps a USDA-backed ingredient to external scientific identifiers
  (`scientific_name`, `ncbi_taxonomy_id`, `foodon_id`, `wikidata_id`) with a
  `confidence` score and `source`/`id_source` provenance. Multiple candidates may
  coexist per ingredient; rows are append-only and never overwritten, so history
  is preserved. A manual verification workflow transitions `status` through
  `candidate → verified` (or `rejected`), superseding any prior verified identity
  via `superseded_by_id`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Food.{Ingredient, IngredientEnrichmentSource, IngredientIdentitySynonym}

  @sources ~w(usda_fdc manual ai external_db)
  @id_sources ~w(wikidata ncbi foodon ols manual)
  @statuses ~w(candidate verified rejected superseded)

  schema "ingredient_scientific_identities" do
    field :scientific_name, :string
    field :rank, :string
    field :ncbi_taxonomy_id, :integer
    field :foodon_id, :string
    field :wikidata_id, :string
    field :source, :string
    field :id_source, :string
    field :confidence, :float
    field :status, :string, default: "candidate"
    field :verified_by_user_id, :id
    field :verified_at, :utc_datetime
    field :notes, :string

    belongs_to :ingredient, Ingredient
    belongs_to :enrichment_source, IngredientEnrichmentSource
    belongs_to :superseded_by, __MODULE__

    has_many :synonyms, IngredientIdentitySynonym, foreign_key: :scientific_identity_id

    timestamps()
  end

  def changeset(identity, attrs) do
    identity
    |> cast(attrs, [
      :ingredient_id,
      :enrichment_source_id,
      :scientific_name,
      :rank,
      :ncbi_taxonomy_id,
      :foodon_id,
      :wikidata_id,
      :source,
      :id_source,
      :confidence,
      :status,
      :verified_by_user_id,
      :verified_at,
      :superseded_by_id,
      :notes
    ])
    |> validate_required([:ingredient_id, :scientific_name, :source, :status])
    |> validate_inclusion(:source, @sources)
    |> validate_inclusion(:id_source, @id_sources)
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint([:ingredient_id, :scientific_name, :source])
    |> unique_constraint(:ingredient_id, name: :one_verified_identity_per_ingredient)
  end
end
