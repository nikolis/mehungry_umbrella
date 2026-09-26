defmodule Mehungry.Repo.Migrations.CreateMealBlueprintPlanMealIngredients do
  use Ecto.Migration

  # A blueprint-plan meal can now hold a recipe **and/or** any number of
  # whole-food ingredients (mirrors the calendar's UserMeal → IngredientUserMeal).
  # The single ingredient that used to live flat on `meal_blueprint_plan_meals`
  # moves into this child table; existing rows are migrated then the flat columns
  # are dropped.
  def up do
    create table(:meal_blueprint_plan_meal_ingredients) do
      add :blueprint_plan_meal_id,
          references(:meal_blueprint_plan_meals, on_delete: :delete_all),
          null: false

      add :ingredient_id, references(:ingredients, on_delete: :delete_all), null: false
      add :quantity, :float
      add :measurement_unit_id, references(:measurement_units, on_delete: :nilify_all)
      add :ingredient_portion_id, references(:ingredient_portions, on_delete: :nilify_all)

      timestamps()
    end

    create index(:meal_blueprint_plan_meal_ingredients, [:blueprint_plan_meal_id])

    # Migrate each existing single-ingredient plan meal into one child row.
    execute """
    INSERT INTO meal_blueprint_plan_meal_ingredients
      (blueprint_plan_meal_id, ingredient_id, quantity, measurement_unit_id,
       ingredient_portion_id, inserted_at, updated_at)
    SELECT id, ingredient_id, quantity, measurement_unit_id, ingredient_portion_id,
           now(), now()
    FROM meal_blueprint_plan_meals
    WHERE ingredient_id IS NOT NULL
    """

    alter table(:meal_blueprint_plan_meals) do
      remove :ingredient_id
      remove :quantity
      remove :measurement_unit_id
      remove :ingredient_portion_id
    end
  end

  def down do
    alter table(:meal_blueprint_plan_meals) do
      add :ingredient_id, references(:ingredients, on_delete: :delete_all)
      add :quantity, :float
      add :measurement_unit_id, references(:measurement_units, on_delete: :nilify_all)
      add :ingredient_portion_id, references(:ingredient_portions, on_delete: :nilify_all)
    end

    # Best-effort: collapse the first child ingredient back onto the meal row.
    execute """
    UPDATE meal_blueprint_plan_meals m
    SET ingredient_id = c.ingredient_id,
        quantity = c.quantity,
        measurement_unit_id = c.measurement_unit_id,
        ingredient_portion_id = c.ingredient_portion_id
    FROM (
      SELECT DISTINCT ON (blueprint_plan_meal_id)
             blueprint_plan_meal_id, ingredient_id, quantity,
             measurement_unit_id, ingredient_portion_id
      FROM meal_blueprint_plan_meal_ingredients
      ORDER BY blueprint_plan_meal_id, id
    ) c
    WHERE m.id = c.blueprint_plan_meal_id
    """

    drop table(:meal_blueprint_plan_meal_ingredients)
  end
end
