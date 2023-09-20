defmodule MehungryWeb.CalendarLive.Components do
  use Phoenix.Component
  use MehungryWeb, :live_component

  embed_templates("components/*")

  def select_recipe_modal(assigns) do
    ~H"""
      <.modal_select_meal   live_action={assigns.live_action}  changeset={assigns.changeset} recipes = {assigns.recipes} />
    """
  end

  def is_open(action, invocations) do
    case action do
      :new ->
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
