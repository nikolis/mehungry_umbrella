defmodule MehungryApi.DailyMealPlanView do
  use MehungryApi, :view
  alias MehungryApi.DailyMealPlanView
  alias MehungryApi.MealView

  def render("index.json", %{daily_meal_plans: daily_meal_plans}) do
    %{data: render_many(daily_meal_plans, DailyMealPlanView, "daily_meal_plan.json")}
  end

  def render("show.json", %{daily_meal_plan: daily_meal_plan}) do
    %{data: render_one(daily_meal_plan, DailyMealPlanView, "daily_meal_plan.json")}
  end

  def render("daily_meal_plan.json", %{daily_meal_plan: daily_meal_plan}) do
    %{
      id: daily_meal_plan.id,
      daily_meal_plan_title: daily_meal_plan.daily_meal_plan_title,
      meal_note: daily_meal_plan.meal_note,
      increasing_number: daily_meal_plan.increasing_number,
      meals: render_many(daily_meal_plan.meals, MealView, "meal.json")
    }
  end
end
