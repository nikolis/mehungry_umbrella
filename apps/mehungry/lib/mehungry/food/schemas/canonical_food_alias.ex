defmodule Mehungry.Food.CanonicalFoodAlias do
  @moduledoc """
  An alias resolving to a `CanonicalFood` ("acerola cherry" → acerola).
  Stored pre-normalized so classifier lookups are normalized-vs-normalized.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.FoodData.Usda.Parser.Normalizer

  schema "canonical_food_aliases" do
    field :alias, :string

    belongs_to :canonical_food, Mehungry.Food.CanonicalFood

    timestamps()
  end

  def changeset(food_alias, attrs) do
    food_alias
    |> cast(attrs, [:alias, :canonical_food_id])
    |> validate_required([:alias, :canonical_food_id])
    |> update_change(:alias, &Normalizer.normalize/1)
    |> unique_constraint(:alias)
  end
end
