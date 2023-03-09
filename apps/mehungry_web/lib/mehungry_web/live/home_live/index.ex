defmodule MehungryWeb.HomeLive.Index do
  use MehungryWeb, :live_view
  use MehungryWeb.Searchable, :transfers_to_search

  import Ecto

  alias Mehungry.Inventory.BasketParams
  alias Mehungry.Inventory
  alias Mehungry.Inventory.ShoppingBasket
  alias Mehungry.Accounts
  alias Mehungry.History

  @impl true
  def mount(_params, session, socket) do
    user = Accounts.get_user_by_session_token(session["user_token"])

    {:ok,
     socket
     |> assign(:user, user)}
  end

  defp apply_action(socket, :index, _params) do
    socket
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  def handle_event("delete_basket", %{"id" => basket_id}, socket) do
    bs = Inventory.get_shopping_basket!(basket_id)
    Inventory.delete_shopping_basket(bs)

    {:noreply,
     socket
     |> assign(:shopping_basket, nil)}
  end
end
