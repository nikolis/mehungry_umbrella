defmodule Mehungry.Repo.Migrations.AddPlanOptionsToApiMealPlanJobs do
  use Ecto.Migration

  # The tracking row now backs every "plan my own week" generation (web calendar,
  # blueprint plans, mobile), not only the mobile API:
  #   * blueprint_id       — the blueprint constraining generation (optional)
  #   * blueprint_plan_id  — when set, the entries are stored on that independent
  #                          blueprint plan instead of the calendar
  #   * mode               — what to do with meals already in the week
  def change do
    alter table(:api_meal_plan_jobs) do
      add :blueprint_id, references(:meal_blueprints, on_delete: :nilify_all)
      add :blueprint_plan_id, references(:meal_blueprint_plans, on_delete: :delete_all)
      add :mode, :string, null: false, default: "fill_gaps"
    end

    create index(:api_meal_plan_jobs, [:user_id, :status])
  end
end
