defmodule Mehungry.Food.IngredientPortion do
  use Ecto.Schema

  @moduledoc """
  IngredientPortion represents the portions of ingredients and connects bassically ingredients with measurmenet Units
  """

  import Ecto.Changeset

  schema "ingredient_portions" do
    field :amount, :float
    field :value, :float
    field :gram_weight, :float
    field :reference_id, :integer
    field :min_year_acquired, :integer
    field :sequence_number, :integer
    # Human-readable portion label taken from USDA `portionDescription` when the
    # portion has no real measurement unit (measureUnit "undetermined"/id 9999).
    field :description, :string

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
      :description,
      :ingredient_id,
      :measurement_unit_id,
      :ingredient_id
    ])
    # A portion no longer requires a measurement_unit: USDA portions with an
    # "undetermined" measureUnit keep only their `description`. It must have at
    # least one of the two so it can still be displayed.
    |> validate_required([:gram_weight])
    |> validate_has_unit_or_description()
  end

  # Display label for a portion: prefer the free-text description (from USDA
  # `portionDescription`), fall back to the linked measurement unit's name.
  def display_name(%__MODULE__{description: desc}) when is_binary(desc) and desc != "", do: desc

  def display_name(%__MODULE__{measurement_unit: %{name: name}}) when is_binary(name), do: name

  def display_name(_), do: nil

  defp validate_has_unit_or_description(changeset) do
    unit_id = get_field(changeset, :measurement_unit_id)
    description = get_field(changeset, :description)

    if is_nil(unit_id) and (is_nil(description) or description == "") do
      add_error(changeset, :description, "portion needs a measurement unit or a description")
    else
      changeset
    end
  end
end
