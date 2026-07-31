defmodule Mehungry.Food.ParserDismembermentAlias do
  @moduledoc "An alias resolving to a `ParserDismemberment` (\"t-bone steak\" → t bone steak)."

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.FoodData.Usda.Parser.Normalizer

  schema "parser_dismemberment_aliases" do
    field :alias, :string

    belongs_to :dismemberment, Mehungry.Food.ParserDismemberment

    timestamps()
  end

  def changeset(dismemberment_alias, attrs) do
    dismemberment_alias
    |> cast(attrs, [:alias, :dismemberment_id])
    |> validate_required([:alias, :dismemberment_id])
    |> update_change(:alias, &Normalizer.normalize/1)
    |> unique_constraint(:alias)
  end
end
