defmodule Mehungry.Food.CanonicalFood do
  @moduledoc """
  The canonical-food lexicon of the USDA description parser — the normalized
  singular name a parse resolves to ("carrot"). Distinct from the `ingredients`
  table (raw USDA rows); grows through seeds and through admin review
  (`Mehungry.Food.ParsedFoods.verify_parsed_food/2`).
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.FoodData.Usda.Parser.Normalizer

  schema "canonical_foods" do
    field :name, :string

    # Semantic embedding of `name` for Mehungry.AI.SemanticMatcher (pgvector
    # cosine search). Populated out-of-band by CanonicalFoodEmbeddingWorker, not
    # cast here. Not loaded by default — select explicitly when needed.
    field :embedding, Pgvector.Ecto.Vector
    field :embedding_model, :string

    has_many :aliases, Mehungry.Food.CanonicalFoodAlias

    timestamps()
  end

  def changeset(food, attrs) do
    food
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> update_change(:name, &Normalizer.normalize/1)
    |> unique_constraint(:name)
  end
end
