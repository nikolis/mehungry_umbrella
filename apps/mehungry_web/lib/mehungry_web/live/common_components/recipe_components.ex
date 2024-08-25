defmodule MehungryWeb.CommonComponents.RecipeComponents do
  @moduledoc false

  import MehungryWeb.CoreComponents
  use Phoenix.Component
  embed_templates("recipe_components/*")

  def get_color(treaty) do
    case treaty do
      true ->
        "#eb4034"

      false ->
        "none"
    end
  end

  def recipe_details(assigns) do
    ~H"""
    <.recipe_details_page
      user_recipes={assigns.user_recipes}
      recipe={assigns.recipe}
      id={@id}
      type={assigns.type}
    />
    """
  end
end
