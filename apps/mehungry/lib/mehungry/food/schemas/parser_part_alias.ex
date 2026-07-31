defmodule Mehungry.Food.ParserPartAlias do
  @moduledoc "An alias resolving to a `ParserPart` (\"top loin\" → loin)."

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.FoodData.Usda.Parser.Normalizer

  schema "parser_part_aliases" do
    field :alias, :string

    belongs_to :part, Mehungry.Food.ParserPart

    timestamps()
  end

  def changeset(part_alias, attrs) do
    part_alias
    |> cast(attrs, [:alias, :part_id])
    |> validate_required([:alias, :part_id])
    |> update_change(:alias, &Normalizer.normalize/1)
    |> unique_constraint(:alias)
  end
end
