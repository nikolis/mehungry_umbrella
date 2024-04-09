defmodule MehungryWeb.UserProfileLive.Index do
  use MehungryWeb, :live_view
  import MehungryWeb.CoreComponents

  alias Mehungry.Accounts
  alias Mehungry.Accounts.UserProfile

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream(socket, :user_profiles, Accounts.list_user_profiles())}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit User profile")
    |> assign(:user_profile, Accounts.get_user_profile!(id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New User profile")
    |> assign(:user_profile, %UserProfile{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing User profiles")
    |> assign(:user_profile, nil)
  end

  @impl true
  def handle_info({MehungryWeb.UserProfileLive.FormComponent, {:saved, user_profile}}, socket) do
    {:noreply, stream_insert(socket, :user_profiles, user_profile)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    user_profile = Accounts.get_user_profile!(id)
    {:ok, _} = Accounts.delete_user_profile(user_profile)

    {:noreply, stream_delete(socket, :user_profiles, user_profile)}
  end
end
