defmodule MehungryWeb.BasketLive.Components do
  use Phoenix.Component

  import Phoenix.HTML.Form
  import MehungryWeb.ErrorHelpers

  embed_templates("components/*")

  def create_basket_modal(assigns) do
    ~H"""
      <.create_basket assigns = {assigns}  live_action = {assigns.live_action} changeset = {assigns.changeset}/>
    """
  end

  def is_open(action, invocations) do
    IO.inspect(action, label: "Is oppen")
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
