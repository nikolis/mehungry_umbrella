defmodule MehungryWeb.CreateRecipeLive.Components do
  use Phoenix.Component
  import Phoenix.HTML.Form
  import MehungryWeb.ErrorHelpers

  embed_templates "forms/*"


  def ingredient_render(assigns) do
    ~H"""
    <.ingredient g={assigns.g} ingredients={assigns.ingredients} measurement_units={assigns.measurement_units}/>
    """
  end

  def step_render(assigns) do
    ~H"""
    <.step v={assigns.v}/>
    """
  end

  def recipe_render(assigns) do
    ~H"""
    <.recipe f={assigns.f}/>
    """
  end

end

