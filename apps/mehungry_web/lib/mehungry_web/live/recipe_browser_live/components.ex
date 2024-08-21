defmodule MehungryWeb.RecipeBrowseLive.Components do
  use Phoenix.Component
  import MehungryWeb.CoreComponents

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
end
