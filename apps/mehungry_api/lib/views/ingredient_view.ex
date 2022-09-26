defmodule MehungryApi.IngredientView do
  use MehungryApi, :view
  alias MehungryApi.IngredientView
  alias MehungryApi.CategoryView
  alias MehungryApi.MeasurementUnitView
  alias MehungryApi.IngredientTranslationView

  def render("index.json", %{ingredients: ingredients}) do
    %{data: render_many(ingredients, IngredientView, "ingredient.json")}
  end

  def render("show.json", %{ingredient: ingredient}) do
    %{data: render_one(ingredient, IngredientView, "ingredient.json")}
  end

  def render("ingredient_complete.json", %{ingredient: ingredient}) do
    %{
      id: ingredient.id,
      url: ingredient.url,
      name: ingredient.name,
      category: render_one(ingredient.category, CategoryView, "category.json"),
      measurement_unit:
        render_one(ingredient.measurement_unit, MeasurementUnitView, "measurement_unit.json"),
      description: ingredient.description,
      ingredient_translation:
        render_many(
          ingredient.ingredient_translation,
          IngredientTranslationView,
          "ingredient_translation.json"
        )
    }
  end

  def render("ingredient_plane.json", %{ingredient: ingredient}) do
    %{
      id: ingredient.id,
      url: ingredient.url,
      name: ingredient.name,
      category: render_one(ingredient.category, CategoryView, "category.json"),
      description: ingredient.description
    }
  end

  def render("ingredient.json", %{ingredient: ingredient}) do
    %{
      id: ingredient.id,
      url: ingredient.url,
      name: ingredient.name,
      category: render_one(ingredient.category, CategoryView, "category.json"),
      measurement_unit:
        render_one(ingredient.measurement_unit, MeasurementUnitView, "measurement_unit.json"),
      description: ingredient.description
    }
  end
end
