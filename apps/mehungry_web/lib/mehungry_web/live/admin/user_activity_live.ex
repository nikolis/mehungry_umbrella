defmodule MehungryWeb.UserActivityLive do
  use MehungryWeb, :live_component
  alias MehungryWeb.Presence

  def update(_assigns, socket) do
    {:ok,
     socket
     |> assign_user_activity()}
  end

  def assign_user_activity(socket) do
    assign(socket, :user_activity, Presence.list_views_and_users())
  end
end
