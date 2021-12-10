defmodule MehungryWeb.IngredientLive.Show do
  use MehungryWeb, :live_view

  alias Mehungry.Food

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _, socket) do
    {:noreply,
     socket
     |> assign(:page_title, page_title(socket.assigns.live_action))
     |> assign(:ingredient, Food.get_ingredient!(id))}
  end

  defp page_title(:show), do: "Show Ingredient"
  defp page_title(:edit), do: "Edit Ingredient"
end
