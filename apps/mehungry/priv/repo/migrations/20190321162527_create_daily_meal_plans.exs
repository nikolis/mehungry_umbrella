defmodule MehungryServer.Repo.Migrations.CreateDailyMealPlans do
  use Ecto.Migration

  def change do
    create table(:daily_meal_plans) do
      add :daily_meal_plan_title, :string
      add :meal_note, :string
      add :increasing_number, :integer
      add :meal_plan_id, references(:meal_plans, on_delete: :nothing)

      timestamps()
    end

    create index(:daily_meal_plans, [:meal_plan_id])
  end
end
