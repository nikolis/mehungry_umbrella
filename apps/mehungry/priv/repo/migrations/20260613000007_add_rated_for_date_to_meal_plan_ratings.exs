defmodule Mehungry.Repo.Migrations.AddRatedForDateToMealPlanRatings do
  use Ecto.Migration

  def change do
    alter table(:meal_plan_ratings) do
      add :rated_for_date, :date
    end

    create unique_index(:meal_plan_ratings, [:user_id, :rated_for_date, :rating_type],
      where: "rated_for_date IS NOT NULL",
      name: :meal_plan_ratings_user_date_type_unique
    )
  end
end
