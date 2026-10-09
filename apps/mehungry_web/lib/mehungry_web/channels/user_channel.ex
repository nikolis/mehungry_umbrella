defmodule MehungryWeb.UserChannel do
  @moduledoc """
  Personal notifications (spec §13 `user:<user_id>`). A socket may only join its
  own topic. The server pushes `"notification"` events (invitations, follows,
  comments, AI-ready) broadcast from the API layer.
  """
  use MehungryWeb, :channel

  @impl true
  def join("user:" <> user_id, _payload, socket) do
    if authorized?(socket, user_id) do
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  defp authorized?(socket, topic_user_id) do
    socket.assigns[:user_id] != nil and to_string(socket.assigns.user_id) == topic_user_id
  end
end
