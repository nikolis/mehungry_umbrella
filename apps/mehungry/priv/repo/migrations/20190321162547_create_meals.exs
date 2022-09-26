defmodule MehungryServer.Repo.Migrations.CreateMeals do
  use Ecto.Migration

  def change do
    create table(:meals) do
      add :meal_title, :string
      add :meal_note, :string
      add :recipe_id, references(:recipes, on_delete: :nothing)
      add :daily_meal_plan_id, references(:daily_meal_plans, on_delete: :nothing)

      timestamps()
    end

    create index(:meals, [:recipe_id])
    create index(:meals, [:daily_meal_plan_id])
  end
end
