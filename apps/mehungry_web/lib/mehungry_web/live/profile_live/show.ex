defmodule MehungryWeb.ProfileLive.Show do
  use MehungryWeb, :live_component

  alias Mehungry.Friends

  @impl true
  # Targeted refresh from the parent's "add_friend" handler — just swap the
  # button state, no re-fetch of the rest of the profile.
  def update(%{friend_status: status}, socket) do
    {:ok, assign(socket, :friend_status, status)}
  end

  def update(%{user_profile: user_profile, user_follows: user_follows} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:user_profile, user_profile)
     |> assign(:user_follows, user_follows)
     |> assign_friend_status()}
  end

  # Relationship between the signed-in user and the profile being viewed, used to
  # decide whether to offer the "Add Friend" button on someone else's profile.
  defp assign_friend_status(socket) do
    current_user = socket.assigns[:current_user]
    user = socket.assigns[:user]

    status =
      if is_nil(current_user) or is_nil(user) do
        :none
      else
        Friends.relationship_status(current_user.id, user.id)
      end

    assign(socket, :friend_status, status)
  end
end
