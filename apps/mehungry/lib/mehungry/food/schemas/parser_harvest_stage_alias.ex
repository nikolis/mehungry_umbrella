defmodule Mehungry.Food.ParserHarvestStageAlias do
  @moduledoc "An alias resolving to a `ParserHarvestStage` (\"young\" → baby)."

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.FoodData.Usda.Parser.Normalizer

  schema "parser_harvest_stage_aliases" do
    field :alias, :string

    belongs_to :harvest_stage, Mehungry.Food.ParserHarvestStage

    timestamps()
  end

  def changeset(stage_alias, attrs) do
    stage_alias
    |> cast(attrs, [:alias, :harvest_stage_id])
    |> validate_required([:alias, :harvest_stage_id])
    |> update_change(:alias, &Normalizer.normalize/1)
    |> unique_constraint(:alias)
  end
end
