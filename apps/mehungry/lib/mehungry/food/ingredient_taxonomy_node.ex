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

  def changeset(ingredient_taxonomy_node, attrs) do
    ingredient_taxonomy_node
    |> cast(attrs, [:source, :confidence, :reviewed, :ingredient_id, :taxonomy_node_id])
    |> validate_required([:source, :ingredient_id, :taxonomy_node_id])
    |> validate_inclusion(:source, @sources)
    |> foreign_key_constraint(:ingredient_id)
    |> foreign_key_constraint(:taxonomy_node_id)
    |> unique_constraint([:ingredient_id, :taxonomy_node_id])
  end
end
