defmodule Mehungry.Food.TaxonomyNode do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Food.{IngredientTaxonomyNode, Taxonomy, TaxonomyNode}

  schema "taxonomy_nodes" do
    field :name, :string
    field :slug, :string
    field :position, :integer, default: 0

    belongs_to :taxonomy, Taxonomy
    belongs_to :parent, TaxonomyNode
    has_many :children, TaxonomyNode, foreign_key: :parent_id
    has_many :ingredient_taxonomy_nodes, IngredientTaxonomyNode

    timestamps()
  end

  def changeset(taxonomy_node, attrs) do
    taxonomy_node
    |> cast(attrs, [:name, :slug, :position, :taxonomy_id, :parent_id])
    |> validate_required([:name, :slug, :taxonomy_id])
    |> foreign_key_constraint(:taxonomy_id)
    |> foreign_key_constraint(:parent_id)
    |> unique_constraint([:taxonomy_id, :slug])
  end
end
