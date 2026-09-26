defmodule Mehungry.MealBlueprints.BlueprintPlanMealIngredient do
  @moduledoc """
  One whole-food ingredient inside a `BlueprintPlanMeal`. A meal can carry a
  recipe **and/or** any number of these ingredient rows — mirrors the calendar's
  `History.UserMeal` → `IngredientUserMeal`.

  Holds the ingredient, a quantity and the resolved unit FKs. `unit_selection`
  is the form-only picker value (positive → a `measurement_unit_id`, negative →
  `-ingredient_portion_id`), parsed by `changeset/2` into the real FKs — identical
  in meaning to `History.IngredientUserMeal.unit_selection`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "meal_blueprint_plan_meal_ingredients" do
    field :quantity, :float

    # Form-only unit picker value; decoded into the real FKs by `changeset/2`.
    field :unit_selection, :integer, virtual: true

    belongs_to :blueprint_plan_meal, Mehungry.MealBlueprints.BlueprintPlanMeal
    belongs_to :ingredient, Mehungry.Food.Ingredient
    belongs_to :measurement_unit, Mehungry.Food.MeasurementUnit
    belongs_to :ingredient_portion, Mehungry.Food.IngredientPortion

    timestamps()
  end

  @doc false
  def changeset(row, attrs) do
    attrs = normalize_unit_selection(attrs)

    row
    |> cast(attrs, [
      :quantity,
      :unit_selection,
      :ingredient_id,
      :measurement_unit_id,
      :ingredient_portion_id
    ])
    |> apply_unit_selection()
    |> validate_required([:ingredient_id])
    |> foreign_key_constraint(:ingredient_id)
  end

  @doc """
  The value the unit dropdown should show as selected for a persisted row:
  `-ingredient_portion_id` for a description-only portion, otherwise the
  `measurement_unit_id`.
  """
  def unit_selection_value(%__MODULE__{measurement_unit_id: nil, ingredient_portion_id: pid})
      when not is_nil(pid),
      do: -pid

  def unit_selection_value(%__MODULE__{measurement_unit_id: mu_id}), do: mu_id

  # Drops a blank `unit_selection` param so casting "" to :integer doesn't add a
  # spurious error when nothing is chosen yet.
  defp normalize_unit_selection(attrs) when is_map(attrs) do
    cond do
      Map.get(attrs, "unit_selection") in ["", nil] and Map.has_key?(attrs, "unit_selection") ->
        Map.delete(attrs, "unit_selection")

      Map.get(attrs, :unit_selection) in ["", nil] and Map.has_key?(attrs, :unit_selection) ->
        Map.delete(attrs, :unit_selection)

      true ->
        attrs
    end
  end

  defp normalize_unit_selection(attrs), do: attrs

  # Splits the form's `unit_selection` into the real FKs. Positive → a real
  # measurement unit; negative → a description-only portion. No-op when nothing
  # was picked (or the caller sent the FKs directly).
  defp apply_unit_selection(changeset) do
    case get_change(changeset, :unit_selection) do
      nil ->
        changeset

      sel when sel >= 0 ->
        changeset
        |> put_change(:measurement_unit_id, sel)
        |> put_change(:ingredient_portion_id, nil)

      sel ->
        changeset
        |> put_change(:ingredient_portion_id, -sel)
        |> put_change(:measurement_unit_id, nil)
    end
  end
end
