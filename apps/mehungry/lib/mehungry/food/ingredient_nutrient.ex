defmodule Mehungry.Food.IngredientNutrient do
  use Ecto.Schema
  @moduledoc false

  import Ecto.Changeset

  schema "ingredient_nutrients" do
    field :median, :float
    field :amount, :float
    field :data_points, :integer
    field :type_, :string

    belongs_to :ingredient, Mehungry.Food.Ingredient
    belongs_to :nutrient, Mehungry.Food.Nutrient

    timestamps()
  end

  @doc false
  def changeset(measurement_unit, attrs) do
    measurement_unit
    |> cast(attrs, [:median, :amount, :data_points, :type_, :ingredient_id, :nutrient_id])
    |> validate_required([:amount, :ingredient_id, :nutrient_id])
  end
end
