defmodule MehungryWeb.ShoppingBasketLiveTest do
  @moduledoc """
  The consumer shopping-basket page (`/basket`). Only the REST basket API was
  tested before this; these cover the LiveView surface itself:

    * the page renders the signed-in user's baskets;
    * the `?basket_id=` deep link (used by the calendar's "Shopping list for the
      week" button) opens the requested basket;
    * adding a plain custom item, toggling/editing/deleting an item, switching
      and deleting a basket all mutate the right rows;
    * a basket id the user does not own cannot be opened (owner-scoped reads);
    * a user with no lists gets the first-run call-to-action.

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

  test "adds a plain custom item to the selected basket (honoring quantity)", %{
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

    # Appears immediately (no reload needed).
    assert html =~ "Olive Oil"

    items = Inventory.get_shopping_basket!(basket.id).basket_items
    assert Enum.any?(items, &(&1.name == "Olive Oil" and &1.quantity == 2.0))
  end

  test "toggles a basket item's acquired state", %{conn: conn, basket: basket} do
    {:ok, item} = Inventory.add_item(basket.id, plain_item("Bread", nil))
    refute item.in_storage

    {:ok, view, _html} = live(conn, ~p"/basket")
    render_click(view, "toggle_basket", %{"id" => to_string(item.id), "type" => "item"})

    reloaded =
      Enum.find(Inventory.get_shopping_basket!(basket.id).basket_items, &(&1.id == item.id))

    assert reloaded.in_storage
  end

  test "edits a basket item's name and quantity", %{conn: conn, basket: basket} do
    {:ok, item} = Inventory.add_item(basket.id, plain_item("Bred", nil))

    {:ok, view, _html} = live(conn, ~p"/basket")

    html =
      render_submit(view, "update_item", %{
        "item_id" => to_string(item.id),
        "item_type" => "item",
        "name" => "Rye Bread",
        "quantity" => "3"
      })

    assert html =~ "Rye Bread"

    reloaded =
      Enum.find(Inventory.get_shopping_basket!(basket.id).basket_items, &(&1.id == item.id))

    assert reloaded.name == "Rye Bread"
    assert reloaded.quantity == 3.0
  end

  test "deletes a basket item", %{conn: conn, basket: basket} do
    {:ok, item} = Inventory.add_item(basket.id, plain_item("Mistake", nil))

    {:ok, view, _html} = live(conn, ~p"/basket")
    html = render_click(view, "delete_item", %{"id" => to_string(item.id), "type" => "item"})

    refute html =~ "Mistake"
    assert Inventory.get_shopping_basket!(basket.id).basket_items == []
  end

  test "switching the selected basket shows its items", %{conn: conn, user: user} do
    {:ok, other} = Inventory.create_shopping_basket(%{user_id: user.id, title: "Camping trip"})
    {:ok, _} = Inventory.add_item(other.id, plain_item("Marshmallows", nil))

    {:ok, view, html} = live(conn, ~p"/basket")
    refute html =~ "Marshmallows"

    html = render_click(view, "select_shopping_basket", %{"id" => to_string(other.id)})
    assert html =~ "Marshmallows"
  end

  test "cannot open another user's basket (owner-scoped)", %{conn: conn} do
    stranger = Mehungry.AccountsFixtures.user_fixture()
    {:ok, theirs} = Inventory.create_shopping_basket(%{user_id: stranger.id, title: "Theirs"})
    {:ok, _} = Inventory.add_item(theirs.id, plain_item("Secret Item", nil))

    {:ok, view, _html} = live(conn, ~p"/basket")
    html = render_click(view, "select_shopping_basket", %{"id" => to_string(theirs.id)})

    refute html =~ "Secret Item"
  end

  test "deletes a basket", %{conn: conn, user: user, basket: basket} do
    {:ok, doomed} = Inventory.create_shopping_basket(%{user_id: user.id, title: "Scratch list"})

    {:ok, view, _html} = live(conn, ~p"/basket")
    render_click(view, "delete_basket", %{"id" => to_string(doomed.id)})

    ids = user.id |> Inventory.list_shopping_baskets_for_user() |> Enum.map(& &1.id)
    assert basket.id in ids
    refute doomed.id in ids
  end

  test "deleting the active basket falls back to another list", %{conn: conn, user: user} do
    # Select a basket, then delete it: the view should fall back to the remaining
    # list rather than keep showing the deleted one.
    {:ok, active} = Inventory.create_shopping_basket(%{user_id: user.id, title: "Active list"})
    {:ok, _} = Inventory.add_item(active.id, plain_item("Vanishing", nil))

    {:ok, view, _html} = live(conn, ~p"/basket")
    html = render_click(view, "select_shopping_basket", %{"id" => to_string(active.id)})
    assert html =~ "Vanishing"

    html = render_click(view, "delete_basket", %{"id" => to_string(active.id)})

    refute html =~ "Vanishing"
    assert html =~ "Weekly groceries"
  end

  test "a user with no lists sees the first-run call to action", %{conn: conn} do
    loner = Mehungry.AccountsFixtures.user_fixture()
    {:ok, _view, html} = live(log_in_user(conn, loner), ~p"/basket")

    assert html =~ "Create your first list"
  end

  test "the add-item modal opens with search and manual entry", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/basket")
    html = render_click(view, "open_add_item_modal", %{})

    assert html =~ "Search for an item"
    assert html =~ "Add manually"
  end

  test "the import-from-calendar route renders the builder", %{conn: conn, basket: basket} do
    {:ok, _view, html} = live(conn, ~p"/basket/import_items/#{basket.id}")
    assert html =~ "Build from a calendar week"
  end

  defp plain_item(name, unit_id) do
    %{name: name, quantity: 1.0, measurement_unit_id: unit_id, nutrition: nil, usda_fdc_id: nil}
  end
end
