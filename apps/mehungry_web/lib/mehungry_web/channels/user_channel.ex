defmodule MehungryWeb.UserChannel do
  @moduledoc """
  Personal notifications (spec §13 `user:<user_id>`). A socket may only join its
  own topic. The server pushes `"notification"` events (invitations, follows,
  comments, AI-ready) broadcast from the API layer.

  On join the socket is tracked in `MehungryWeb.Presence` on its own topic so
  the push layer (`MehungryWeb.Api.PushDispatch`) can tell the user is connected
  and skip the OS push (they already got the live broadcast).
  """
  use MehungryWeb, :channel

  alias MehungryWeb.Presence

  @impl true
  def join("user:" <> user_id, _payload, socket) do
    if authorized?(socket, user_id) do
      send(self(), :after_join)
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  @impl true
  def handle_info(:after_join, socket) do
    {:ok, _ref} =
      Presence.track(socket, to_string(socket.assigns.user_id), %{
        online_at: System.system_time(:second)
      })

    {:noreply, socket}
  end

  defp authorized?(socket, topic_user_id) do
    socket.assigns[:user_id] != nil and to_string(socket.assigns.user_id) == topic_user_id
  end
end
