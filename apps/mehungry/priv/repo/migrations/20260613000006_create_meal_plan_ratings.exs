defmodule Mehungry.Repo.Migrations.CreateMealPlanRatings do
  use Ecto.Migration

  def change do
    create table(:meal_plan_ratings) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :rating_type, :string, null: false
      add :daily_meal_plan_id, references(:daily_meal_plans, on_delete: :delete_all)
      add :meal_plan_id, references(:meal_plans, on_delete: :delete_all)
      add :score, :integer, null: false
      add :comment, :text

      timestamps()
    end

    create index(:meal_plan_ratings, [:user_id])
    create unique_index(:meal_plan_ratings, [:user_id, :daily_meal_plan_id],
      where: "daily_meal_plan_id IS NOT NULL",
      name: :meal_plan_ratings_user_daily_unique
    )
    create unique_index(:meal_plan_ratings, [:user_id, :meal_plan_id],
      where: "meal_plan_id IS NOT NULL",
      name: :meal_plan_ratings_user_weekly_unique
    )
  end
end
