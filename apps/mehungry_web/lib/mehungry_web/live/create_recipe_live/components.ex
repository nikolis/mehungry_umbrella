defmodule MehungryWeb.CreateRecipeLive.Components do
  use Phoenix.Component

  use PhoenixHTMLHelpers
  import MehungryWeb.CoreComponents

  embed_templates("components/*")

  def ingredient_render(assigns) do
    assigns = assign(assigns, :deleted, Phoenix.HTML.Form.input_value(assigns.g, :delete) == true)

    ~H"""
    <.ingredient g={assigns.g} ingredients={assigns.ingredients} measurement_units={assigns.measurement_units} style={get_style(assigns.deleted)}  deleted={assigns.deleted}/>
    """
  end

  def get_style(deleted) do
    if(deleted) do
      "display: none;"
    else
      "display: block;"
    end
  end

  def step_render(assigns) do
    assigns = assign(assigns, :deleted, Phoenix.HTML.Form.input_value(assigns.v, :delete) == true)

    ~H"""
    <.step v={assigns.v} deleted={assigns.deleted}/>
    """
  end

  def recipe_render(assigns) do
    ~H"""
    <.recipe f={assigns.f}/>
    """
  end
end
