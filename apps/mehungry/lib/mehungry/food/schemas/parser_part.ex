defmodule Mehungry.Food.ParserPart do
  @moduledoc "A USDA primal/body-part descriptor of the parser (loin, chuck, breast)."

  use Ecto.Schema

  import Ecto.Changeset

  schema "parser_parts" do
    field :name, :string

    has_many :aliases, Mehungry.Food.ParserPartAlias, foreign_key: :part_id

    timestamps()
  end

  def changeset(part, attrs) do
    part
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end
end
