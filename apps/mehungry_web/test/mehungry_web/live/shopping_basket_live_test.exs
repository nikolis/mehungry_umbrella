defmodule MehungryWeb.ShoppingBasketLiveTest do
  @moduledoc """
  The consumer shopping-basket page (`/basket`). Only the REST basket API was
  tested before this; these cover the LiveView surface itself:

    * the page renders the signed-in user's baskets;
    * the `?basket_id=` deep link (used by the calendar's "Shopping list for the
      week" button) opens the requested basket;
    * adding a plain custom item, toggling an item checked, switching the
      selected basket, and deleting a basket all mutate the right rows.

  The USDA-search add path hits an external client and is covered by the API
  tests / `SearchClient` — it is intentionally not driven here.
  """
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mehungry.FoodFixtures, only: [measurement_unit_fixture: 0]

  alias Mehungry.Inventory

  setup %{conn: conn} do
    user = Mehungry.AccountsFixtures.user_fixture()
    unit = measurement_unit_fixture()

    {:ok, basket} =
      Inventory.create_shopping_basket(%{user_id: user.id, title: "Weekly groceries"})

    %{conn: log_in_user(conn, user), user: user, unit: unit, basket: basket}
  end

  test "renders the signed-in user's basket", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/basket")
    assert html =~ "Weekly groceries"
  end

  test "the ?basket_id= deep link opens the requested basket", %{
    conn: conn,
    user: user,
    basket: basket
  } do
    {:ok, other} =
      Inventory.create_shopping_basket(%{user_id: user.id, title: "Party list"})

    {:ok, _} = Inventory.add_item(other.id, plain_item("Confetti cake", nil))

    {:ok, _view, html} = live(conn, ~p"/basket?basket_id=#{other.id}")

    # The main panel shows the deep-linked basket's item, not the default one.
    assert html =~ "Confetti cake"

    # Sanity: deep-linking the original basket does not show the other's item.
    {:ok, _view, html} = live(conn, ~p"/basket?basket_id=#{basket.id}")
    refute html =~ "Confetti cake"
  end

  test "adds a plain custom item to the selected basket", %{
    conn: conn,
    unit: unit,
    basket: basket
  } do
    {:ok, view, _html} = live(conn, ~p"/basket")

    html =
      render_click(view, "add_plain_item", %{
        "basket_item" => %{"measurement_unit_id" => to_string(unit.id)},
        "name" => "Olive Oil",
        "quantity" => "2"
      })

    assert html =~ "Olive Oil"

    items = Inventory.get_shopping_basket!(basket.id).basket_items
    assert Enum.any?(items, &(&1.name == "Olive Oil" and &1.quantity == 2.0))
  end

  test "toggles a basket item's checked state", %{conn: conn, basket: basket} do
    {:ok, item} = Inventory.add_item(basket.id, plain_item("Bread", nil))
    refute item.in_storage

    {:ok, view, _html} = live(conn, ~p"/basket")
    render_click(view, "toggle_basket", %{"id" => to_string(item.id)})

    reloaded = Enum.find(Inventory.get_shopping_basket!(basket.id).basket_items, &(&1.id == item.id))
    assert reloaded.in_storage
  end

  test "switching the selected basket shows its items", %{conn: conn, user: user} do
    {:ok, other} = Inventory.create_shopping_basket(%{user_id: user.id, title: "Camping trip"})
    {:ok, _} = Inventory.add_item(other.id, plain_item("Marshmallows", nil))

    {:ok, view, html} = live(conn, ~p"/basket")
    refute html =~ "Marshmallows"

    html = render_click(view, "select_shopping_basket", %{"id" => to_string(other.id)})
    assert html =~ "Marshmallows"
  end

  test "deletes a basket", %{conn: conn, user: user, basket: basket} do
    {:ok, doomed} = Inventory.create_shopping_basket(%{user_id: user.id, title: "Scratch list"})

    {:ok, view, _html} = live(conn, ~p"/basket")
    render_click(view, "delete_basket", %{"id" => to_string(doomed.id)})

    ids = user.id |> Inventory.list_shopping_baskets_for_user() |> Enum.map(& &1.id)
    assert basket.id in ids
    refute doomed.id in ids
  end

  defp plain_item(name, unit_id) do
    %{name: name, quantity: 1.0, measurement_unit_id: unit_id, nutrition: nil, usda_fdc_id: nil}
  end
end
