defmodule MehungryWeb.RecipeBrowseLive.Components do
  use Phoenix.Component

  embed_templates("components/*")

  def get_color(treaty) do
    case treaty do
      true ->
        "#eb4034"

      false ->
        "none"
    end
  end
end
