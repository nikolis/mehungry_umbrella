defmodule MehungryWeb.UserIngredientRuleLive.Index do
  use MehungryWeb, :live_view
  import MehungryWeb.CoreComponents

  alias Mehungry.Accounts
  alias Mehungry.Accounts.UserIngredientRule

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream(socket, :user_ingredient_rules, Accounts.list_user_ingredient_rules())}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit User ingredient rule")
    |> assign(:user_ingredient_rule, Accounts.get_user_ingredient_rule!(id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New User ingredient rule")
    |> assign(:user_ingredient_rule, %UserIngredientRule{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing User ingredient rules")
    |> assign(:user_ingredient_rule, nil)
  end

  @impl true
  def handle_info(
        {MehungryWeb.UserIngredientRuleLive.FormComponent, {:saved, user_ingredient_rule}},
        socket
      ) do
    {:noreply, stream_insert(socket, :user_ingredient_rules, user_ingredient_rule)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    user_ingredient_rule = Accounts.get_user_ingredient_rule!(id)
    {:ok, _} = Accounts.delete_user_ingredient_rule(user_ingredient_rule)

    {:noreply, stream_delete(socket, :user_ingredient_rules, user_ingredient_rule)}
  end
end
