defmodule MehungryWeb.SnackNutsTest do
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mehungry.FoodFixtures, only: [ingredient_fixture: 1]
  import Mehungry.AccountsFixtures

  alias Mehungry.Food.{Category, SnackIngredients}
  alias Mehungry.Repo

  @admin_email Application.compile_env(:mehungry, :admin_email)

  setup %{conn: conn} do
    admin = user_fixture(%{email: @admin_email})

    nuts =
      Repo.insert!(%Category{
        name: "Nut test #{System.unique_integer([:positive])}",
        description: "nuts"
      })

    almond =
      ingredient_fixture(%{name: "Aaa test almonds"})
      |> Ecto.Changeset.change(category_id: nuts.id)
      |> Repo.update!()

    %{conn: log_in_user(conn, admin), admin: admin, almond: almond}
  end

  test "lists nut candidates, adds and removes one", %{conn: conn, almond: a, admin: admin} do
    {:ok, view, html} = live(conn, ~p"/professional/snack-nuts")
    assert html =~ "Snack foods"

    view |> form("#snack-search-form", %{search: "aaa test"}) |> render_change()
    assert has_element?(view, "#candidate-#{a.id}", "Aaa test almonds")
    refute has_element?(view, "#selected-#{a.id}")

    view |> element("#candidate-#{a.id} button[phx-click=add]") |> render_click()

    assert has_element?(view, "#selected-#{a.id}", "Aaa test almonds")
    assert has_element?(view, "#candidate-#{a.id}", "Added")
    assert [%{added_by_id: admin_id}] = SnackIngredients.list_selected()
    assert admin_id == admin.id

    view |> element("#selected-#{a.id} button[phx-click=remove]") |> render_click()

    refute has_element?(view, "#selected-#{a.id}")
    assert SnackIngredients.selected_ids() == MapSet.new()
  end

  test "search filters candidates", %{conn: conn, almond: a} do
    {:ok, view, _html} = live(conn, ~p"/professional/snack-nuts")

    view |> form("#snack-search-form", %{search: "walnut"}) |> render_change()
    refute has_element?(view, "#candidate-#{a.id}")

    view |> form("#snack-search-form", %{search: "aaa test alm"}) |> render_change()
    assert has_element?(view, "#candidate-#{a.id}")
  end

  test "fresh fruit tab curates its own kind", %{conn: conn, almond: a} do
    fruit =
      Repo.insert!(%Category{
        name: "Fruit test #{System.unique_integer([:positive])}",
        description: "fruit"
      })

    peach =
      ingredient_fixture(%{name: "Aaa test peaches"})
      |> Ecto.Changeset.change(category_id: fruit.id)
      |> Repo.update!()

    {:ok, view, _html} = live(conn, ~p"/professional/snack-nuts")
    view |> element("#tab-fresh_fruit") |> render_click()
    assert_patch(view, ~p"/professional/snack-nuts?kind=fresh_fruit")

    view |> form("#snack-search-form", %{search: "aaa test"}) |> render_change()
    assert has_element?(view, "#candidate-#{peach.id}")
    # The almond is in a nut category, not a fruit one.
    refute has_element?(view, "#candidate-#{a.id}")

    view |> element("#candidate-#{peach.id} button[phx-click=add]") |> render_click()

    assert SnackIngredients.selected_ids("fresh_fruit") == MapSet.new([peach.id])
    assert SnackIngredients.selected_ids("dried_nut") == MapSet.new()
  end

  test "non-admins are redirected" do
    conn = log_in_user(build_conn(), user_fixture())
    assert {:error, {_kind, _}} = live(conn, ~p"/professional/snack-nuts")
  end
end
