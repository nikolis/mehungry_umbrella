defmodule MehungryWeb.SearchSelectLiveTest do
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mehungry.ComponentsFixtures

  @create_attrs %{}
  @update_attrs %{}
  @invalid_attrs %{}

  defp create_search_select(_) do
    search_select = search_select_fixture()
    %{search_select: search_select}
  end

  describe "Index" do
    setup [:create_search_select]

    test "lists all search_selects", %{conn: conn} do
      {:ok, _index_live, html} = live(conn, ~p"/search_selects")

      assert html =~ "Listing Search selects"
    end

    test "saves new search_select", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/search_selects")

      assert index_live |> element("a", "New Search select") |> render_click() =~
               "New Search select"

      assert_patch(index_live, ~p"/search_selects/new")

      assert index_live
             |> form("#search_select-form", search_select: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#search_select-form", search_select: @create_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/search_selects")

      html = render(index_live)
      assert html =~ "Search select created successfully"
    end

    test "updates search_select in listing", %{conn: conn, search_select: search_select} do
      {:ok, index_live, _html} = live(conn, ~p"/search_selects")

      assert index_live
             |> element("#search_selects-#{search_select.id} a", "Edit")
             |> render_click() =~
               "Edit Search select"

      assert_patch(index_live, ~p"/search_selects/#{search_select}/edit")

      assert index_live
             |> form("#search_select-form", search_select: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#search_select-form", search_select: @update_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/search_selects")

      html = render(index_live)
      assert html =~ "Search select updated successfully"
    end

    test "deletes search_select in listing", %{conn: conn, search_select: search_select} do
      {:ok, index_live, _html} = live(conn, ~p"/search_selects")

      assert index_live
             |> element("#search_selects-#{search_select.id} a", "Delete")
             |> render_click()

      refute has_element?(index_live, "#search_selects-#{search_select.id}")
    end
  end

  describe "Show" do
    setup [:create_search_select]

    test "displays search_select", %{conn: conn, search_select: search_select} do
      {:ok, _show_live, html} = live(conn, ~p"/search_selects/#{search_select}")

      assert html =~ "Show Search select"
    end

    test "updates search_select within modal", %{conn: conn, search_select: search_select} do
      {:ok, show_live, _html} = live(conn, ~p"/search_selects/#{search_select}")

      assert show_live |> element("a", "Edit") |> render_click() =~
               "Edit Search select"

      assert_patch(show_live, ~p"/search_selects/#{search_select}/show/edit")

      assert show_live
             |> form("#search_select-form", search_select: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert show_live
             |> form("#search_select-form", search_select: @update_attrs)
             |> render_submit()

      assert_patch(show_live, ~p"/search_selects/#{search_select}")

      html = render(show_live)
      assert html =~ "Search select updated successfully"
    end
  end
end
