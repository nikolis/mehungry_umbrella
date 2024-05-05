defmodule MehungryWeb.RecipeBrowseLive.Components do
  use Phoenix.Component
  embed_templates("components/*")
  alias Phoenix.LiveView.JS


  def get_color(treaty) do
    case treaty do
      true ->
        "#eb4034"

      false ->
        "none"
    end
  end

  def recipe_modal(assigns) do
    if assigns.recipe do
    end

    case assigns.recipe do
      nil ->
        ~H"""
        """

      _recipe ->
       

        ~H"""
        <.recipe_modal_page  invocations={assigns.invocations} live_action={assigns.live_action} recipe={assigns.recipe} nutrients = {assigns.nutrients}/>
        """
    end
  end

  alias Phoenix.LiveView.JS

  def hide_modal(js \\ %JS{}) do
    js
    |> JS.hide(transition: "fade-out", to: "#modal2")
  end

end
