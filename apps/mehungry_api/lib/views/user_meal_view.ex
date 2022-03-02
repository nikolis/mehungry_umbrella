defmodule MehungryApi.UserMealView do
  use MehungryApi, :view
  alias MehungryApi.UserMealView
  alias MehungryApi.RecipeView

  def render("index.json", %{history_user_meals: history_user_meals}) do
    %{data: render_many(history_user_meals, UserMealView, "user_meal_complete.json")}
  end

  def render("user_meal_complete.json", %{user_meal: user_meal}) do
    %{
      id: user_meal.id,
      title: user_meal.title,
      meal_datetime: user_meal.meal_datetime,
      recipes:
        Enum.map(user_meal.recipe_user_meals, fn um_rec ->
          render_one(um_rec.recipe, RecipeView, "recipe.json")
        end)
    }
  end

  def render("show.json", %{user_meal: user_meal}) do
    %{data: render_one(user_meal, UserMealView, "user_meal.json")}
  end

  def render("user_meal.json", %{user_meal: user_meal}) do
    %{
      id: user_meal.id,
      title: user_meal.title,
      meal_datetime: user_meal.meal_datetime
    }
  end
end
