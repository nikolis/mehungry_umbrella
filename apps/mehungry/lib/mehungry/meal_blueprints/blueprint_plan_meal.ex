defmodule Mehungry.MealBlueprints.BlueprintPlanMeal do
  @moduledoc """
  One planned meal inside a generated `BlueprintPlan`, held **independently of
  the calendar**. A row is either a recipe (`recipe_id` + `cooking_portions`) or
  a whole-food ingredient (`ingredient_id` + `quantity` + resolved unit FKs).

  Days are relative (`day_index` 1..7) and slots are canonical
  `History.MealType` values — the row carries no calendar date. Importing a plan
  maps these onto a chosen start date and creates `History.UserMeal` rows.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "meal_blueprint_plan_meals" do
    field :day_index, :integer
    field :meal_type, :string
    field :cooking_portions, :integer
    field :quantity, :float

    # Form-only unit picker value, identical in meaning to
    # `History.IngredientUserMeal.unit_selection`: positive → a
    # `measurement_unit_id`, negative → `-ingredient_portion_id` (a
    # description-only portion). Parsed by `changeset/2` into the real FKs.
    field :unit_selection, :integer, virtual: true

    belongs_to :blueprint_plan, Mehungry.MealBlueprints.BlueprintPlan
    belongs_to :recipe, Mehungry.Food.Recipe
    belongs_to :ingredient, Mehungry.Food.Ingredient
    belongs_to :measurement_unit, Mehungry.Food.MeasurementUnit
    belongs_to :ingredient_portion, Mehungry.Food.IngredientPortion

    timestamps()
  end

  @doc false
  def changeset(plan_meal, attrs) do
    attrs = normalize_unit_selection(attrs)

    plan_meal
    |> cast(attrs, [
      :day_index,
      :meal_type,
      :cooking_portions,
      :quantity,
      :unit_selection,
      :blueprint_plan_id,
      :recipe_id,
      :ingredient_id,
      :measurement_unit_id,
      :ingredient_portion_id
    ])
    |> apply_unit_selection()
    |> validate_required([:day_index, :meal_type, :blueprint_plan_id])
    |> validate_recipe_or_ingredient()
    |> foreign_key_constraint(:blueprint_plan_id)
    |> foreign_key_constraint(:recipe_id)
    |> foreign_key_constraint(:ingredient_id)
  end

  @doc """
  The value the unit dropdown should show as selected for a persisted ingredient
  row: `-ingredient_portion_id` for a description-only portion, otherwise the
  `measurement_unit_id`. Mirrors `History.IngredientUserMeal.unit_selection_value/1`.
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

  defp validate_recipe_or_ingredient(changeset) do
    recipe_id = get_field(changeset, :recipe_id)
    ingredient_id = get_field(changeset, :ingredient_id)

    cond do
      not is_nil(recipe_id) and not is_nil(ingredient_id) ->
        add_error(changeset, :recipe_id, "a plan meal cannot be both a recipe and an ingredient")

      is_nil(recipe_id) and is_nil(ingredient_id) ->
        add_error(changeset, :recipe_id, "a plan meal needs a recipe or an ingredient")

      true ->
        changeset
    end
  end
end
