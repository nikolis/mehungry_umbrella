defmodule Mehungry.Food.MeasurementUnit do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Food.MeasurementUnitTranslation

  schema "measurement_units" do
    field :name, :string
    field :alternate_name, :string
    field :url, :string
    # USDA NDB number preserved when a numeric-named unit is reconciled to its
    # real food description. See Mehungry.Food.Measurements.reconcile_measurement_unit/2.
    field :ndb_number, :string

    has_many :ingredient_portions, Mehungry.Food.IngredientPortion
    has_many :translation, MeasurementUnitTranslation
    timestamps()
  end

  @doc false
  def changeset(measurement_unit, attrs) do
    measurement_unit
    |> cast(attrs, [:url, :name, :alternate_name, :ndb_number])
    |> cast_assoc(:translation, with: &Mehungry.Food.MeasurementUnitTranslation.changeset/2)
    |> validate_required([:name])
    |> unique_constraint(:name)
  end
end
