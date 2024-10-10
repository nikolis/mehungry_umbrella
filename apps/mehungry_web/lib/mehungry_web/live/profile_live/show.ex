defmodule MehungryWeb.ProfileLive.Show do
  use MehungryWeb, :live_component

  @impl true
  def update(%{user_profile: user_profile, user_follows: user_follows} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:user_profile, user_profile)
     |> assign(:user_follows, user_follows)}
  end
end
