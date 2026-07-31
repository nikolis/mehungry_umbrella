defmodule Mehungry.Food.ParserHarvestStage do
  @moduledoc "A harvest stage of the USDA description parser (baby, mature)."

  use Ecto.Schema

  import Ecto.Changeset

  schema "parser_harvest_stages" do
    field :name, :string

    has_many :aliases, Mehungry.Food.ParserHarvestStageAlias, foreign_key: :harvest_stage_id

    timestamps()
  end

  def changeset(stage, attrs) do
    stage
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end
end
