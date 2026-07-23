defmodule Mehungry.Food.TaxonomyNode do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Food.{Taxonomy, IngredientTaxonomyNode}

  schema "taxonomy_nodes" do
    field :name, :string
    field :slug, :string
    field :position, :integer, default: 0

    belongs_to :taxonomy, Taxonomy
    belongs_to :parent, __MODULE__

    has_many :children, __MODULE__, foreign_key: :parent_id
    has_many :ingredient_taxonomy_nodes, IngredientTaxonomyNode

    timestamps()
  end

  def changeset(node, attrs) do
    node
    |> cast(attrs, [:name, :slug, :position, :taxonomy_id, :parent_id])
    |> validate_required([:name, :slug, :taxonomy_id])
    |> unique_constraint(:slug, name: :taxonomy_nodes_taxonomy_id_slug_index)
  end
end
