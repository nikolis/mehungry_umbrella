defmodule Mehungry.Repo.Migrations.CreateMealBlueprintPlans do
  use Ecto.Migration

  def change do
    create table(:meal_blueprint_plans) do
      add :name, :string, null: false
      add :start_date, :date, null: false
      add :status, :string, null: false, default: "generating"
      add :meals_count, :integer, null: false, default: 0
      add :error, :string

      add :blueprint_id,
          references(:meal_blueprints, on_delete: :delete_all),
          null: false

      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:meal_blueprint_plans, [:blueprint_id])
    create index(:meal_blueprint_plans, [:user_id])

    # Tag the calendar meals a generation run produced back to their plan, so a
    # blueprint can list its generated plans (and their meals) without a join
    # table. Nilify (not cascade) so deleting a plan leaves the meals on the
    # calendar untouched.
    alter table(:history_user_meals) do
      add :blueprint_plan_id,
          references(:meal_blueprint_plans, on_delete: :nilify_all)
    end

    create index(:history_user_meals, [:blueprint_plan_id])
  end
end
