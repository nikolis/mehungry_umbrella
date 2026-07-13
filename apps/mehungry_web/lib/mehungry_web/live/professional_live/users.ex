defmodule MehungryWeb.ProfessionalLive.Users do
  use MehungryWeb, :live_view

  alias Mehungry.Accounts
  alias Mehungry.Accounts.User
  alias Mehungry.Food
  alias Mehungry.Subscriptions

  @default_filters %{
    "confirmation" => "all",
    "activity" => "all",
    "registered" => "all",
    "q" => ""
  }

  @impl true
  def mount(_params, _session, socket) do
    subscriptions = Subscriptions.subscriptions_by_user_id()

    pro_count =
      Enum.count(subscriptions, fn {_id, sub} -> sub.tier in ["m3hungry_plus", "pro"] end)

    socket =
      socket
      |> assign(:subscriptions, subscriptions)
      |> assign(:pro_count, pro_count)
      |> assign(:recipe_counts, Food.recipe_counts_by_user_id())
      |> assign(:total_count, Accounts.count_users())
      |> assign(:filters, @default_filters)
      |> assign(:confirm_delete_user, nil)
      |> load_users()

    {:ok, socket}
  end

  @impl true
  def handle_event("filter", params, socket) do
    filters = Map.merge(@default_filters, Map.take(params, Map.keys(@default_filters)))
    {:noreply, socket |> assign(:filters, filters) |> load_users()}
  end

  @impl true
  def handle_event("clear_filters", _params, socket) do
    {:noreply, socket |> assign(:filters, @default_filters) |> load_users()}
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
     |> assign(:shown_count, max(socket.assigns.shown_count - 1, 0))
     |> assign(:total_count, max(socket.assigns.total_count - 1, 0))
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

  defp load_users(socket) do
    users =
      socket.assigns.filters
      |> Accounts.list_users()
      |> apply_activity_filter(socket.assigns.filters["activity"], socket.assigns.recipe_counts)

    socket
    |> assign(:shown_count, length(users))
    |> stream(:users, users, reset: true)
  end

  defp apply_activity_filter(users, "with_recipes", counts),
    do: Enum.filter(users, &(Map.get(counts, &1.id, 0) > 0))

  defp apply_activity_filter(users, "no_recipes", counts),
    do: Enum.filter(users, &(Map.get(counts, &1.id, 0) == 0))

  defp apply_activity_filter(users, _activity, _counts), do: users
end
