defmodule Mehungry.Food.IngredientCompoundRelationship do
  @moduledoc """
  A scientific fact linking an ingredient to a `Compound` —
  e.g. *Spinach contains Oxalate*, *Broccoli contains Sulforaphane*.

  Provenance-rich (`source`, `confidence`, optional `enrichment_source_id`
  citation) and append-friendly: the same `(ingredient, compound,
  relationship_type, source)` is deduped, but the same pairing from a different
  source or under a different relationship type is kept as a separate row.

  Facts only — `notes` is free-form factual text; this layer never stores
  recommendations or dietary advice.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Food.{Ingredient, Compound, IngredientEnrichmentSource}

  @relationship_types ~w(contains high_in low_in trace absent)
  @sources ~w(manual ai literature external_db)

  schema "ingredient_compound_relationships" do
    field :relationship_type, :string, default: "contains"
    field :confidence, :float
    field :source, :string
    field :notes, :string

    belongs_to :ingredient, Ingredient
    belongs_to :compound, Compound
    belongs_to :enrichment_source, IngredientEnrichmentSource

    timestamps()
  end

  def changeset(relationship, attrs) do
    relationship
    |> cast(attrs, [
      :ingredient_id,
      :compound_id,
      :enrichment_source_id,
      :relationship_type,
      :confidence,
      :source,
      :notes
    ])
    |> validate_required([:ingredient_id, :compound_id, :relationship_type, :source])
    |> validate_inclusion(:relationship_type, @relationship_types)
    |> validate_inclusion(:source, @sources)
    |> unique_constraint([:ingredient_id, :compound_id, :relationship_type, :source])
  end
end
