defmodule Mehungry.Food.ParserProcessingAlias do
  @moduledoc """
  An alias resolving to a `ParserProcessingMethod`. `head_template` marks
  aliases that may head a `"X, <ingredient>"` template ("oil", "pickle");
  `implied_canonical_food_id` carries the food such a head implies when none
  is explicit ("pickle" → cucumber).
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.FoodData.Usda.Parser.Normalizer

  schema "parser_processing_aliases" do
    field :alias, :string
    field :head_template, :boolean, default: false

    belongs_to :processing_method, Mehungry.Food.ParserProcessingMethod
    belongs_to :implied_canonical_food, Mehungry.Food.CanonicalFood

    timestamps()
  end

  def changeset(processing_alias, attrs) do
    processing_alias
    |> cast(attrs, [:alias, :head_template, :processing_method_id, :implied_canonical_food_id])
    |> validate_required([:alias, :processing_method_id])
    |> update_change(:alias, &Normalizer.normalize/1)
    |> unique_constraint(:alias)
  end
end
