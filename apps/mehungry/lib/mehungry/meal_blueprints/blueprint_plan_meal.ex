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

    belongs_to :blueprint_plan, Mehungry.MealBlueprints.BlueprintPlan
    belongs_to :recipe, Mehungry.Food.Recipe
    belongs_to :ingredient, Mehungry.Food.Ingredient
    belongs_to :measurement_unit, Mehungry.Food.MeasurementUnit
    belongs_to :ingredient_portion, Mehungry.Food.IngredientPortion

    timestamps()
  end

  @doc false
  def changeset(plan_meal, attrs) do
    plan_meal
    |> cast(attrs, [
      :day_index,
      :meal_type,
      :cooking_portions,
      :quantity,
      :blueprint_plan_id,
      :recipe_id,
      :ingredient_id,
      :measurement_unit_id,
      :ingredient_portion_id
    ])
    |> validate_required([:day_index, :meal_type, :blueprint_plan_id])
    |> validate_recipe_or_ingredient()
    |> foreign_key_constraint(:blueprint_plan_id)
    |> foreign_key_constraint(:recipe_id)
    |> foreign_key_constraint(:ingredient_id)
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
