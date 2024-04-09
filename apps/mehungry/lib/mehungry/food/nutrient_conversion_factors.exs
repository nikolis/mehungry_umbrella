defmodule Mehungry.Food.NutrientConversionFactors do
  use Ecto.Schema
  @moduledoc false

  import Ecto.Changeset

  schema "nutrientconversionfactors" do
    field :carbohydrate_value, :float
    field :fat_value, :float
    field :protein_value, :float

    field :protein_conversion_factor_value, :float
    field :type_, :string

    # FoodData Central Data Types  https://fdc.nal.usda.gov/download-datasets.html
    field :rank, :integer
    field :number, :string
    field :reference_id, :integer

    belongs_to :measurement_unit, Mehungry.Food.MeasurementUnit

    timestamps()
  end

  @doc false
  def changeset(nutrient, attrs) do
    nutrient
    |> cast(attrs, [:description, :family, :rank, :number, :reference_id, :name])
    |> validate_required([:name, :number, :rank])
    |> unique_constraint([:name])
  end
end
