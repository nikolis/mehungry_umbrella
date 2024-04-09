defmodule MehungryWeb.UserCategoryRuleLive.Index do
  use MehungryWeb, :live_view
  import MehungryWeb.CoreComponents

  alias Mehungry.Accounts
  alias Mehungry.Accounts.UserCategoryRule

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream(socket, :user_category_rules, Accounts.list_user_category_rules())}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit User category rule")
    |> assign(:user_category_rule, Accounts.get_user_category_rule!(id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New User category rule")
    |> assign(:user_category_rule, %UserCategoryRule{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing User category rules")
    |> assign(:user_category_rule, nil)
  end

  @impl true
  def handle_info(
        {MehungryWeb.UserCategoryRuleLive.FormComponent, {:saved, user_category_rule}},
        socket
      ) do
    {:noreply, stream_insert(socket, :user_category_rules, user_category_rule)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    user_category_rule = Accounts.get_user_category_rule!(id)
    {:ok, _} = Accounts.delete_user_category_rule(user_category_rule)

    {:noreply, stream_delete(socket, :user_category_rules, user_category_rule)}
  end
end
