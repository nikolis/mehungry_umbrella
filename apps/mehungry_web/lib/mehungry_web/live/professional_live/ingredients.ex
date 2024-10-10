defmodule MehungryWeb.ProfessionalLive.Ingredients do
  use MehungryWeb, :live_view

  @topic "user_activity"
  def mount(_params, _session, socket) do
    active_users = MehungryWeb.Presence.list_products_and_users()
    MehungryWeb.Endpoint.subscribe(@topic)
    socket = assign(socket, :active_users, active_users)
    {:ok, socket}
  end

  def handle_info(%{event: "presence_diff"}, socket) do
    active_users = MehungryWeb.Presence.list_products_and_users()
    socket = assign(socket, :active_users, active_users)

    {:noreply, socket}
  end
end
