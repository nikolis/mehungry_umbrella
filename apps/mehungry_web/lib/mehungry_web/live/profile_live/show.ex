defmodule MehungryWeb.ProfileLive.Show do
  use MehungryWeb, :live_component

  import MehungryWeb.CoreComponents

  @impl true
  def update(%{user_profile: user_profile} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:user_profile, user_profile)}
  end
end
