defmodule MehungryWeb.BasketChannel do
  @moduledoc """
  Live updates for one shopping list (spec §13 `basket:<basket_id>`). Only the
  list's owner and members may join. The server pushes `"basket_changed"`
  (`{basket_id}`) whenever the list, its items or its people change, from any
  client; the app then refetches `GET /api/v1/baskets/:id`. A subscriber who
  has lost access (removed, or the list was deleted) gets `"basket_closed"` and
  is disconnected from the topic.

  The topic is the same PubSub topic `Mehungry.Inventory` broadcasts on, so the
  channel process receives the core's `{:basket_changed, id}` message directly.
  """
  use MehungryWeb, :channel

  alias Mehungry.Inventory

  @impl true
  def join("basket:" <> basket_id, _payload, socket) do
    with user_id when not is_nil(user_id) <- socket.assigns[:user_id],
         {id, ""} <- Integer.parse(basket_id),
         true <- Inventory.can_access_basket?(user_id, id) do
      {:ok, assign(socket, :basket_id, id)}
    else
      _ -> {:error, %{reason: "unauthorized"}}
    end
  end

  @impl true
  def handle_info({:basket_changed, basket_id}, socket) do
    if Inventory.can_access_basket?(socket.assigns.user_id, basket_id) do
      push(socket, "basket_changed", %{basket_id: basket_id})
      {:noreply, socket}
    else
      close(socket, basket_id)
    end
  end

  def handle_info({:basket_deleted, basket_id}, socket), do: close(socket, basket_id)
  def handle_info(_message, socket), do: {:noreply, socket}

  defp close(socket, basket_id) do
    push(socket, "basket_closed", %{basket_id: basket_id})
    {:stop, :normal, socket}
  end
end
