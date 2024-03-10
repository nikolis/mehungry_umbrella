"""
defmodule MehungryWeb.TestingerLiveTest do
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mehungry.TestFixtures

  @create_attrs %{name: "some name"}
  @update_attrs %{name: "some updated name"}
  @invalid_attrs %{name: nil}

  defp create_testinger(_) do
    testinger = testinger_fixture()
    %{testinger: testinger}
  end

  describe "Index" do
    setup [:create_testinger]

    test "lists all testingers", %{conn: conn, testinger: testinger} do
      {:ok, _index_live, html} = live(conn, ~p"/testingers")

      assert html =~ "Listing Testingers"
      assert html =~ testinger.name
    end

    test "saves new testinger", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/testingers")

      assert index_live |> element("a", "New Testinger") |> render_click() =~
               "New Testinger"

      assert_patch(index_live, ~p"/testingers/new")

      assert index_live
             |> form("#testinger-form", testinger: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#testinger-form", testinger: @create_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/testingers")

      html = render(index_live)
      assert html =~ "Testinger created successfully"
      assert html =~ "some name"
    end

    test "updates testinger in listing", %{conn: conn, testinger: testinger} do
      {:ok, index_live, _html} = live(conn, ~p"/testingers")

      assert index_live |> element("#testingers-#{testinger.id} a", "Edit") |> render_click() =~
               "Edit Testinger"

      assert_patch(index_live, ~p"/testingers/#{testinger}/edit")

      assert index_live
             |> form("#testinger-form", testinger: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#testinger-form", testinger: @update_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/testingers")

      html = render(index_live)
      assert html =~ "Testinger updated successfully"
      assert html =~ "some updated name"
    end

    test "deletes testinger in listing", %{conn: conn, testinger: testinger} do
      {:ok, index_live, _html} = live(conn, ~p"/testingers")

      assert index_live |> element("#testingers-#{testinger.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#testingers-#{testinger.id}")
    end
  end

  describe "Show" do
    setup [:create_testinger]

    test "displays testinger", %{conn: conn, testinger: testinger} do
      {:ok, _show_live, html} = live(conn, ~p"/testingers/#{testinger}")

      assert html =~ "Show Testinger"
      assert html =~ testinger.name
    end

    test "updates testinger within modal", %{conn: conn, testinger: testinger} do
      {:ok, show_live, _html} = live(conn, ~p"/testingers/#{testinger}")

      assert show_live |> element("a", "Edit") |> render_click() =~
               "Edit Testinger"

      assert_patch(show_live, ~p"/testingers/#{testinger}/show/edit")

      assert show_live
             |> form("#testinger-form", testinger: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert show_live
             |> form("#testinger-form", testinger: @update_attrs)
             |> render_submit()

      assert_patch(show_live, ~p"/testingers/#{testinger}")

      html = render(show_live)
      assert html =~ "Testinger updated successfully"
      assert html =~ "some updated name"
    end
  end
end
"""
