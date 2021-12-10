defmodule Mehungry.Food.MeasurementUnit do
  use Ecto.Schema

  import Ecto.Changeset
  
  alias Mehungry.Food.MeasurementUnitTranslation


  schema "measurement_units" do
    field :name, :string
    field :url, :string

    has_many :translation, MeasurementUnitTranslation
    timestamps()
  end

  @doc false
  def changeset(measurement_unit, attrs) do
    measurement_unit
    |> cast(attrs, [:url, :name])
    |> cast_assoc(:translation, with: &Mehungry.Food.MeasurementUnitTranslation.changeset/2)
    |> validate_required([:name])
    |> unique_constraint(:name)
  end


end
