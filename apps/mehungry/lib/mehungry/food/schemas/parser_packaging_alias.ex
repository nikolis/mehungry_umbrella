defmodule Mehungry.Food.ParserPackagingAlias do
  @moduledoc "An alias resolving to a packaging value (\"jarred\" → canned)."

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.FoodData.Usda.Parser.Normalizer

  schema "parser_packaging_aliases" do
    field :alias, :string
    field :packaging, :string

    timestamps()
  end

  def changeset(packaging_alias, attrs) do
    packaging_alias
    |> cast(attrs, [:alias, :packaging])
    |> validate_required([:alias, :packaging])
    |> update_change(:alias, &Normalizer.normalize/1)
    |> unique_constraint(:alias)
  end
end
