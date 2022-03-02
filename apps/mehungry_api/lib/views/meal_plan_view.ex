defmodule MehungryApi.MealPlanView do
  use MehungryApi, :view
  alias MehungryApi.MealPlanView
  alias MehungryApi.DailyMealPlanView

  def render("index.json", %{meal_plans: meal_plans}) do
    %{data: render_many(meal_plans, MealPlanView, "meal_plan.json")}
  end

  def render("show.json", %{meal_plan: meal_plan}) do
    %{data: render_one(meal_plan, MealPlanView, "meal_plan.json")}
  end

  def render("meal_plan.json", %{meal_plan: meal_plan}) do
    %{
      id: meal_plan.id,
      title: meal_plan.title,
      description: meal_plan.description,
      daily_meail_plans:
        render_many(meal_plan.daily_meal_plans, DailyMealPlanView, "daily_meal_plan.json")
    }
  end
end
