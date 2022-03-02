defmodule MehungryApi.IngredientTranslationView do
  use MehungryApi, :view

  def render("ingredient_translation.json", %{ingredient_translation: ingredient_translation}) do
    %{
      id: ingredient_translation.id,
      name: ingredient_translation.name,
      description: ingredient_translation.description,
      url: ingredient_translation.url
    }
  end
end
