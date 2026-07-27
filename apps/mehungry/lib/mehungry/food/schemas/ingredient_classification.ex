defmodule Mehungry.Food.IngredientClassification do
  @moduledoc """
  Scientific classification of an ingredient — per-ingredient binomial /
  species naming and external references (GBIF/EOL/ITIS).

  A hierarchical classification tree can additionally be modelled with the
  existing `Taxonomy` / `TaxonomyNode` structures; this schema holds the flat,
  per-ingredient scientific attributes.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Food.{Ingredient, IngredientEnrichmentSource}

  @sources ~w(manual ai literature external_db)

  schema "ingredient_classifications" do
    field :scientific_name, :string
    field :genus, :string
    field :species, :string
    field :cultivar, :string
    field :rank, :string
    field :external_ref, :string
    field :source, :string
    field :confidence, :float
    field :reviewed, :boolean, default: false
    field :retrieved_at, :utc_datetime

    belongs_to :ingredient, Ingredient
    belongs_to :enrichment_source, IngredientEnrichmentSource

    timestamps()
  end

  def changeset(classification, attrs) do
    classification
    |> cast(attrs, [
      :ingredient_id,
      :enrichment_source_id,
      :scientific_name,
      :genus,
      :species,
      :cultivar,
      :rank,
      :external_ref,
      :source,
      :confidence,
      :reviewed,
      :retrieved_at
    ])
    |> validate_required([:ingredient_id, :scientific_name, :source])
    |> validate_inclusion(:source, @sources)
    |> unique_constraint([:ingredient_id, :scientific_name])
  end
end
