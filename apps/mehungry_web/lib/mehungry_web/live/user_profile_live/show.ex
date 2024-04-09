defmodule MehungryWeb.UserProfileLive.Show do
  use MehungryWeb, :live_view
  import MehungryWeb.CoreComponents

  alias Mehungry.Accounts

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _, socket) do
    {:noreply,
     socket
     |> assign(:page_title, page_title(socket.assigns.live_action))
     |> assign(:user_profile, Accounts.get_user_profile!(id))}
  end

  defp page_title(:show), do: "Show User profile"
  defp page_title(:edit), do: "Edit User profile"
end
