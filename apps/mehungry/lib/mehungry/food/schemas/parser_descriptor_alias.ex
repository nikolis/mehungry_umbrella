defmodule Mehungry.Food.ParserDescriptorAlias do
  @moduledoc """
  A free-standing descriptor of the USDA description parser. `kind` is one of:

  - `"not_food"` — the description is skipped ("alcoholic beverage")
  - `"modifier"` — becomes a processing modifier ("dill", "chopped")
  - `"noise"` — dropped silently without a confidence penalty ("nfs")
  - `"bone_state"` — sets `result.bone_state` ("boneless", "bone in")
  - `"portion"` — appended to `result.portion` ("meat only", "skinless")
  - `"grade"` — sets `result.grade` (USDA quality grade, "choice")
  - `"prepared"` — the description is skipped as a composite dish ("commercial")
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.FoodData.Usda.Parser.Normalizer

  @kinds ~w(not_food modifier noise bone_state portion grade prepared)

  schema "parser_descriptor_aliases" do
    field :alias, :string
    field :kind, :string

    timestamps()
  end

  def kinds, do: @kinds

  def changeset(descriptor, attrs) do
    descriptor
    |> cast(attrs, [:alias, :kind])
    |> validate_required([:alias, :kind])
    |> validate_inclusion(:kind, @kinds)
    |> update_change(:alias, &Normalizer.normalize/1)
    |> unique_constraint(:alias)
  end
end
