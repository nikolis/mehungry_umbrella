defmodule MehungryWeb.BasketChannel do
  @moduledoc """
  Live updates for one shopping list (spec §13 `basket:<basket_id>`). Only the
  list's owner and members may join.

  A client that joins with `{"v": 2}` is sent single-item changes **with the
  item**, so it patches its copy without a refetch: `"item_upserted"`
  (`{basket_id, item, actor_id}`, `item` in the `GET /baskets/:id` item shape)
  and `"item_deleted"` (`{basket_id, id, actor_id}`). Everything else — a bulk
  import, a rename, the people on the list — is `"basket_changed"`
  (`{basket_id}`), a poke to refetch `GET /api/v1/baskets/:id`. A client that
  joins without `v` (apps released before the item events) gets the poke for
  every change.

  A subscriber who has lost access (removed, or the list was deleted) gets
  `"basket_closed"` and is disconnected from the topic.

  The topic is the same PubSub topic `Mehungry.Inventory` broadcasts on, so the
  channel process receives the core's messages directly (see
  `Mehungry.Inventory.subscribe/1`).
  """
  use MehungryWeb, :channel

  alias Mehungry.Inventory
  alias Mehungry.Inventory.BasketItem
  alias MehungryWeb.Api.V1.BasketJSON

  @impl true
  def join("basket:" <> basket_id, payload, socket) do
    with user_id when not is_nil(user_id) <- socket.assigns[:user_id],
         {id, ""} <- Integer.parse(basket_id),
         true <- Inventory.can_access_basket?(user_id, id) do
      {:ok, socket |> assign(:basket_id, id) |> assign(:proto, proto(payload))}
    else
      _ -> {:error, %{reason: "unauthorized"}}
    end
  end

  # The protocol the client asked for at join: 2 = item events, 1 = pokes only.
  defp proto(%{"v" => v}) when is_integer(v) and v >= 2, do: 2
  defp proto(_payload), do: 1

  @impl true
  def handle_info({:basket_changed, basket_id}, socket) do
    if_member(socket, basket_id, fn ->
      push(socket, "basket_changed", %{basket_id: basket_id})
    end)
  end

  def handle_info({:basket_entry, basket_id, %{op: op, entry: entry} = change}, socket) do
    if_member(socket, basket_id, fn ->
      push_entry(socket, basket_id, op, entry, Map.get(change, :actor_id))
    end)
  end

  def handle_info({:basket_deleted, basket_id}, socket), do: close(socket, basket_id)
  def handle_info(_message, socket), do: {:noreply, socket}

  # Access is re-checked on every message: a removed member must not be sent
  # another change.
  defp if_member(socket, basket_id, push_fun) do
    if Inventory.can_access_basket?(socket.assigns.user_id, basket_id) do
      push_fun.()
      {:noreply, socket}
    else
      close(socket, basket_id)
    end
  end

  defp push_entry(
         %{assigns: %{proto: 2}} = socket,
         basket_id,
         :upsert,
         %BasketItem{} = item,
         actor
       ) do
    aisle = [item] |> Inventory.aisle_for_items() |> Map.get(item.id, "other")

    push(socket, "item_upserted", %{
      basket_id: basket_id,
      item: BasketJSON.item(item, aisle),
      actor_id: actor
    })
  end

  defp push_entry(
         %{assigns: %{proto: 2}} = socket,
         basket_id,
         :delete,
         %BasketItem{id: id},
         actor
       ) do
    push(socket, "item_deleted", %{basket_id: basket_id, id: id, actor_id: actor})
  end

  # Pre-item-event clients, and lines the API does not serialize as items
  # (recipe-derived `BasketIngredient`s): a poke to refetch.
  defp push_entry(socket, basket_id, _op, _entry, _actor) do
    push(socket, "basket_changed", %{basket_id: basket_id})
  end

  defp close(socket, basket_id) do
    push(socket, "basket_closed", %{basket_id: basket_id})
    {:stop, :normal, socket}
  end
end
