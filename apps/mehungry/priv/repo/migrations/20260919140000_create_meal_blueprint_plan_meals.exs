defmodule Mehungry.Repo.Migrations.CreateMealBlueprintPlanMeals do
  use Ecto.Migration

  def change do
    # The contents of a generated plan, held **independently of the calendar**.
    # Generation writes these rows; nothing lands on the calendar until the user
    # explicitly imports a plan (which then creates history_user_meals stamped
    # with blueprint_plan_id). Days are relative (1..7), not calendar dates.
    create table(:meal_blueprint_plan_meals) do
      add :blueprint_plan_id,
          references(:meal_blueprint_plans, on_delete: :delete_all),
          null: false

      add :day_index, :integer, null: false
      add :meal_type, :string, null: false

      # Exactly one of recipe_id / ingredient_id is set per row.
      add :recipe_id, references(:recipes, on_delete: :delete_all)
      add :cooking_portions, :integer

      add :ingredient_id, references(:ingredients, on_delete: :delete_all)
      add :quantity, :float
      add :measurement_unit_id, references(:measurement_units, on_delete: :nilify_all)
      add :ingredient_portion_id, references(:ingredient_portions, on_delete: :nilify_all)

      timestamps()
    end

    create index(:meal_blueprint_plan_meals, [:blueprint_plan_id])

    # Marker for whether a plan has ever been imported to the calendar (re-import
    # is allowed; this just flags it for the UI).
    alter table(:meal_blueprint_plans) do
      add :imported_at, :naive_datetime
    end
  end
end
