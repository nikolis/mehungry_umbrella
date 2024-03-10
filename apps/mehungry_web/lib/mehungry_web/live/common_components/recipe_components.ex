defmodule MehungryWeb.CommonComponents.RecipeComponents do
  @moduledoc false

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
    <.recipe_details_page  recipe={assigns.recipe}  />
    """
  end

  def recipe_modal(assigns) do
    case assigns.recipe do
      nil ->
        ~H"""
        """

      _recipe ->
        ~H"""
        <.recipe_modal_page  invocations={assigns.invocations} live_action={assigns.live_action} recipe={assigns.recipe} />
        """
    end
  end

  def is_open(action, invocations) do
    case action do
      :show ->
        "is-open"

      _ ->
        if invocations > 1 do
          "is-closing"
        else
          "is-closed"
        end
    end
  end
end
