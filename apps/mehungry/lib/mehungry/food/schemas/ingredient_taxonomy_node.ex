defmodule Mehungry.Food.IngredientTaxonomyNode do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Food.{Ingredient, TaxonomyNode}

  @sources ~w(usda_seed ai manual)

  schema "ingredient_taxonomy_nodes" do
    field :source, :string
    field :confidence, :float
    field :reviewed, :boolean, default: false

    belongs_to :ingredient, Ingredient
    belongs_to :taxonomy_node, TaxonomyNode

    timestamps()
  end

  def changeset(mapping, attrs) do
    mapping
    |> cast(attrs, [:ingredient_id, :taxonomy_node_id, :source, :confidence, :reviewed])
    |> validate_required([:ingredient_id, :taxonomy_node_id, :source])
    |> validate_inclusion(:source, @sources)
    |> unique_constraint([:ingredient_id, :taxonomy_node_id])
  end
end
