defmodule MehungryWeb.NuserLive.Show do
  use MehungryWeb, :live_view

  alias Mehungry.NewsLetter

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _, socket) do
    {:noreply,
     socket
     |> assign(:page_title, page_title(socket.assigns.live_action))
     |> assign(:nuser, NewsLetter.get_nuser!(id))}
  end

  defp page_title(:show), do: "Show Nuser"
  defp page_title(:edit), do: "Edit Nuser"
end
