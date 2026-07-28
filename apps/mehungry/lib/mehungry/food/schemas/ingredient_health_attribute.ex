defmodule Mehungry.Food.IngredientHealthAttribute do
  @moduledoc """
  Health / dietary attributes attached to an ingredient — namespaced flags such
  as `allergen:gluten`, `fodmap:high`, `diet:vegan`. `value` carries an optional
  level/severity.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Food.{Ingredient, IngredientEnrichmentSource}

  @sources ~w(manual ai literature external_db)

  schema "ingredient_health_attributes" do
    field :attribute, :string
    field :value, :string
    field :source, :string
    field :confidence, :float
    field :reviewed, :boolean, default: false
    field :retrieved_at, :utc_datetime

    belongs_to :ingredient, Ingredient
    belongs_to :enrichment_source, IngredientEnrichmentSource

    timestamps()
  end

  def changeset(attribute, attrs) do
    attribute
    |> cast(attrs, [
      :ingredient_id,
      :enrichment_source_id,
      :attribute,
      :value,
      :source,
      :confidence,
      :reviewed,
      :retrieved_at
    ])
    |> validate_required([:ingredient_id, :attribute, :source])
    |> validate_inclusion(:source, @sources)
    |> unique_constraint([:ingredient_id, :attribute, :source])
  end
end
