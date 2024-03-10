defmodule Mehungry.Repo.Migrations.CreateConsumeRecipeUserMeals do
  use Ecto.Migration

  def change do
    create table(:history_consume_recipe_user_meals) do
      add :consume_portions, :integer
      add :start_dt, :naive_datetime
      add :end_dt, :naive_datetime

      add :recipe_user_meal_id, references(:history_recipe_user_meals)
      add :user_meal_id, references(:history_user_meals)
    end
  end
end
