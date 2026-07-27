defmodule Mehungry.Food.IngredientScientificProperty do
  @moduledoc """
  Bioactive / compound measures attached to an ingredient (glycemic index,
  ORAC, total polyphenols…).

  Kept deliberately separate from `IngredientNutrient` because that table is
  delete-then-recreated by the USDA reconciliation worker; enrichment stored
  here survives reconciliation.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Food.{Ingredient, IngredientEnrichmentSource}

  @sources ~w(manual ai literature external_db)

  schema "ingredient_scientific_properties" do
    field :property_key, :string
    field :value, :float
    field :unit, :string
    field :basis, :string
    field :source, :string
    field :confidence, :float
    field :reviewed, :boolean, default: false
    field :retrieved_at, :utc_datetime

    belongs_to :ingredient, Ingredient
    belongs_to :enrichment_source, IngredientEnrichmentSource

    timestamps()
  end

  def changeset(property, attrs) do
    property
    |> cast(attrs, [
      :ingredient_id,
      :enrichment_source_id,
      :property_key,
      :value,
      :unit,
      :basis,
      :source,
      :confidence,
      :reviewed,
      :retrieved_at
    ])
    |> validate_required([:ingredient_id, :property_key, :source])
    |> validate_inclusion(:source, @sources)
    |> unique_constraint([:ingredient_id, :property_key, :source])
  end
end
