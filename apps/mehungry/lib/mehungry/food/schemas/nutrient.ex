defmodule Mehungry.Food.Nutrient do
  use Ecto.Schema
  @moduledoc false

  import Ecto.Changeset

  schema "nutrients" do
    field :name, :string
    field :description, :string

    field :alternate_name, :string
    field :family, :string

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
    |> cast(attrs, [
      :alternate_name,
      :description,
      :family,
      :rank,
      :number,
      :reference_id,
      :name,
      :measurement_unit_id
    ])
    |> validate_required([:name, :rank])
    |> unique_constraint([:name, :measurement_unit_id])
  end
end
