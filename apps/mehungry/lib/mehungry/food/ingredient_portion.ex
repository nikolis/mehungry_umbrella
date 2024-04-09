defmodule Mehungry.Food.IngredientPortion do
  use Ecto.Schema
  @moduledoc false

  import Ecto.Changeset

  schema "ingredient_portions" do
    field :amount, :float
    field :value, :float
    field :gram_weight, :float
    field :reference_id, :integer
    field :min_year_acquired, :integer
    field :sequence_number, :integer

    belongs_to :ingredient, Mehungry.Food.Ingredient

    belongs_to :measurement_unit, Mehungry.Food.MeasurementUnit

    timestamps()
  end

  @doc false
  def changeset(measurement_unit, attrs) do
    measurement_unit
    |> cast(attrs, [
      :value,
      :min_year_acquired,
      :reference_id,
      :gram_weight,
      :amount,
      :ingredient_id,
      :measurement_unit_id,
      :ingredient_id
    ])
    |> validate_required([:amount, :gram_weight, :ingredient_id, :min_year_acquired])
  end
end
