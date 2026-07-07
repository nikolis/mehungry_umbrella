defmodule MehungryWeb.ProfessionalLive.Users do
  use MehungryWeb, :live_view

  alias Mehungry.Accounts
  alias Mehungry.Accounts.User
  alias Mehungry.Subscriptions

  @impl true
  def mount(_params, _session, socket) do
    subscriptions = Subscriptions.subscriptions_by_user_id()

    pro_count =
      Enum.count(subscriptions, fn {_id, sub} -> sub.tier in ["m3hungry_plus", "pro"] end)

    {:ok,
     socket
     |> assign(:subscriptions, subscriptions)
     |> assign(:pro_count, pro_count)
     |> assign(:confirm_delete_user, nil)
     |> stream(:users, Accounts.list_users())}
  end

  @impl true
  def handle_event("confirm_delete", %{"user-id" => id, "user-email" => email}, socket) do
    {:noreply, assign(socket, :confirm_delete_user, %{id: String.to_integer(id), email: email})}
  end

  @impl true
  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, :confirm_delete_user, nil)}
  end

  @impl true
  def handle_event("delete_user", %{"id" => id}, socket) do
    user = Accounts.get_user!(id)
    Accounts.delete_user(user)

    {:noreply,
     socket
     |> assign(:confirm_delete_user, nil)
     |> stream_delete(:users, user)
     |> put_flash(:info, "User #{user.email} deleted.")}
  end

  @impl true
  def handle_event("reset", %{"value" => ""}, socket) do
    {:noreply, stream(socket, :users, [], reset: true)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit User")
    |> assign(:user, Accounts.get_user!(id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New User")
    |> assign(:user, %User{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing Users")
    |> assign(:user, nil)
  end

  @impl true
  def handle_info({MehungryWeb.UserLive.FormComponent, {:saved, user}}, socket) do
    {:noreply, stream_insert(socket, :users, user)}
  end
end
