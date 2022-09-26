defmodule MehungryApi.MealView do
  use MehungryApi, :view

  alias MehungryApi.MealView
  alias MehungryApi.RecipeView

  def render("index.json", %{meals: meals}) do
    %{data: render_many(meals, MealView, "meal.json")}
  end

  def render("show.json", %{meal: meal}) do
    %{data: render_one(meal, MealView, "meal.json")}
  end

  def render("meal.json", %{meal: meal}) do
    %{
      id: meal.id,
      meal_title: meal.meal_title,
      meal_note: meal.meal_note,
      recipe: render_one(meal.recipe, RecipeView, "recipe.json")
    }
  end
end
