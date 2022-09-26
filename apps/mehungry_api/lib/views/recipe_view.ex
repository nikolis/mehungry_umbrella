defmodule MehungryApi.RecipeView do
  use MehungryApi, :view

  alias MehungryApi.RecipeView
  alias MehungryApi.RecipeIngredientView
  alias MehungryApi.UserView
  alias MehungryApi.StepView

  def render("index.json", %{recipes: recipes}) do
    %{data: render_many(recipes, RecipeView, "recipe_minimal.json")}
  end

  def render("show.json", %{recipe: recipe}) do
    %{data: render_one(recipe, RecipeView, "recipe.json")}
  end

  def translate_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, &translate_error/1)
  end

  def render("error.json", %{changeset: changeset}) do
    %{error: translate_errors(changeset)}
  end

  def render("step.json", %{step: step}) do
    %{
      title: step.title,
      description: step.description
    }
  end

  def render("recipe_minimal.json", %{recipe: recipe}) do
    %{
      id: recipe.id,
      user_id: recipe.user_id,
      servings: recipe.servings,
      cousine: recipe.cousine,
      title: recipe.title,
      author: recipe.author,
      original_url: recipe.original_url,
      preperation_time_upper_limit: recipe.preperation_time_upper_limit,
      preperation_time_lower_limit: recipe.preperation_time_lower_limit,
      cooking_time_upper_limit: recipe.cooking_time_upper_limit,
      cooking_time_lower_limit: recipe.cooking_time_lower_limit,
      image_url: recipe.image_url,
      recipe_image_remote: recipe.recipe_image_remote,
      description: recipe.description,
      user: render_one(recipe.user, UserView, "user.json")
    }
  end

  def render("recipe.json", %{recipe: recipe}) do
    %{
      id: recipe.id,
      user_id: recipe.user_id,
      servings: recipe.servings,
      cousine: recipe.cousine,
      title: recipe.title,
      author: recipe.author,
      original_url: recipe.original_url,
      preperation_time_upper_limit: recipe.preperation_time_upper_limit,
      preperation_time_lower_limit: recipe.preperation_time_lower_limit,
      cooking_time_upper_limit: recipe.cooking_time_upper_limit,
      cooking_time_lower_limit: recipe.cooking_time_lower_limit,
      description: recipe.description,
      image_url: recipe.image_url,
      recipe_image_remote: recipe.recipe_image_remote,
      steps: render_many(recipe.steps, StepView, "step.json"),
      # user: render_one(recipe.user, UserView, "user.json"),
      recipe_ingredients:
        render_many(recipe.recipe_ingredients, RecipeIngredientView, "recipe_ingredient.json")
    }
  end
end
