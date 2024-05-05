defmodule MehungryWeb.LiveHelpers do
  @moduledoc false

  import Phoenix.Component

  alias Phoenix.LiveView.JS

  def modal_large(assigns) do
    assigns = assign_new(assigns, :return_to, fn -> nil end)

    ~H"""
    <div id="modal" class="phx-modal fade-in w-full " phx-remove={hide_modal()}>
      <div
        id="modal-content"
        class="phx-modal-content-large fade-in-scale rounded-xl w-full"
        phx-click-away={JS.dispatch("click", to: "#close")}
        phx-window-keydown={JS.dispatch("click", to: "#close")}
        phx-key="escape"
      >
        <%= render_slot(@inner_block) %>
      </div>
    </div>
    """
  end

  defp hide_modal(js \\ %JS{}) do
    js
    |> JS.hide(to: "#modal", transition: "fade-out")
    |> JS.hide(to: "#modal-content", transition: "fade-out-scale")
  end
end
