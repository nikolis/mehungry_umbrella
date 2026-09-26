defmodule Mehungry.MealBlueprints.BlueprintPlanMeal do
  @moduledoc """
  One planned meal inside a generated `BlueprintPlan`, held **independently of
  the calendar**. A meal may carry a recipe (`recipe_id` + `cooking_portions`)
  **and/or** any number of whole-food ingredients (`has_many :ingredients` →
  `BlueprintPlanMealIngredient`) — the same shape as a calendar `History.UserMeal`.

  Days are relative (`day_index` 1..7) and slots are canonical
  `History.MealType` values — the row carries no calendar date. Importing a plan
  maps these onto a chosen start date and creates `History.UserMeal` rows.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Mehungry.MealBlueprints.BlueprintPlanMealIngredient

  schema "meal_blueprint_plan_meals" do
    field :day_index, :integer
    field :meal_type, :string
    field :cooking_portions, :integer

    belongs_to :blueprint_plan, Mehungry.MealBlueprints.BlueprintPlan
    belongs_to :recipe, Mehungry.Food.Recipe

    has_many :ingredients, BlueprintPlanMealIngredient,
      foreign_key: :blueprint_plan_meal_id,
      on_delete: :delete_all,
      on_replace: :delete

    timestamps()
  end

  @doc false
  def changeset(plan_meal, attrs) do
    plan_meal
    |> cast(attrs, [
      :day_index,
      :meal_type,
      :cooking_portions,
      :blueprint_plan_id,
      :recipe_id
    ])
    |> cast_assoc(:ingredients, with: &BlueprintPlanMealIngredient.changeset/2)
    |> validate_required([:day_index, :meal_type, :blueprint_plan_id])
    |> validate_recipe_or_ingredients()
    |> foreign_key_constraint(:blueprint_plan_id)
    |> foreign_key_constraint(:recipe_id)
  end

  # A meal must resolve to something edible: either a recipe or at least one
  # (non-deleted) ingredient child.
  defp validate_recipe_or_ingredients(changeset) do
    if is_nil(get_field(changeset, :recipe_id)) and not has_ingredients?(changeset) do
      add_error(changeset, :recipe_id, "a plan meal needs a recipe or at least one ingredient")
    else
      changeset
    end
  end

  defp has_ingredients?(changeset) do
    case get_change(changeset, :ingredients) do
      nil ->
        case changeset.data.ingredients do
          list when is_list(list) -> list != []
          _ -> false
        end

      changes ->
        Enum.any?(changes, &(&1.action not in [:replace, :delete]))
    end
  end
end
