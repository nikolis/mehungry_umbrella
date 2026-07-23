defmodule Mehungry.Food.Taxonomy do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Food.TaxonomyNode

  schema "taxonomies" do
    field :name, :string
    field :slug, :string
    field :description, :string

    has_many :nodes, TaxonomyNode

    timestamps()
  end

  def changeset(taxonomy, attrs) do
    taxonomy
    |> cast(attrs, [:name, :slug, :description])
    |> validate_required([:name, :slug])
    |> unique_constraint(:slug)
  end
end
