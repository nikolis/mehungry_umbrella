defmodule MehungryWeb.U2serLiveTest do
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mehungry.Accounts2Fixtures

  @create_attrs %{age: 42, name: "some name"}
  @update_attrs %{age: 43, name: "some updated name"}
  @invalid_attrs %{age: nil, name: nil}

  defp create_u2ser(_) do
    u2ser = u2ser_fixture()
    %{u2ser: u2ser}
  end

  describe "Index" do
    setup [:create_u2ser]

    test "lists all u2sers", %{conn: conn, u2ser: u2ser} do
      {:ok, _index_live, html} = live(conn, Routes.u2ser_index_path(conn, :index))

      assert html =~ "Listing U2sers"
      assert html =~ u2ser.name
    end

    test "saves new u2ser", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, Routes.u2ser_index_path(conn, :index))

      assert index_live |> element("a", "New U2ser") |> render_click() =~
               "New U2ser"

      assert_patch(index_live, Routes.u2ser_index_path(conn, :new))

      assert index_live
             |> form("#u2ser-form", u2ser: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      {:ok, _, html} =
        index_live
        |> form("#u2ser-form", u2ser: @create_attrs)
        |> render_submit()
        |> follow_redirect(conn, Routes.u2ser_index_path(conn, :index))

      assert html =~ "U2ser created successfully"
      assert html =~ "some name"
    end

    test "updates u2ser in listing", %{conn: conn, u2ser: u2ser} do
      {:ok, index_live, _html} = live(conn, Routes.u2ser_index_path(conn, :index))

      assert index_live |> element("#u2ser-#{u2ser.id} a", "Edit") |> render_click() =~
               "Edit U2ser"

      assert_patch(index_live, Routes.u2ser_index_path(conn, :edit, u2ser))

      assert index_live
             |> form("#u2ser-form", u2ser: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      {:ok, _, html} =
        index_live
        |> form("#u2ser-form", u2ser: @update_attrs)
        |> render_submit()
        |> follow_redirect(conn, Routes.u2ser_index_path(conn, :index))

      assert html =~ "U2ser updated successfully"
      assert html =~ "some updated name"
    end

    test "deletes u2ser in listing", %{conn: conn, u2ser: u2ser} do
      {:ok, index_live, _html} = live(conn, Routes.u2ser_index_path(conn, :index))

      assert index_live |> element("#u2ser-#{u2ser.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#u2ser-#{u2ser.id}")
    end
  end

  describe "Show" do
    setup [:create_u2ser]

    test "displays u2ser", %{conn: conn, u2ser: u2ser} do
      {:ok, _show_live, html} = live(conn, Routes.u2ser_show_path(conn, :show, u2ser))

      assert html =~ "Show U2ser"
      assert html =~ u2ser.name
    end

    test "updates u2ser within modal", %{conn: conn, u2ser: u2ser} do
      {:ok, show_live, _html} = live(conn, Routes.u2ser_show_path(conn, :show, u2ser))

      assert show_live |> element("a", "Edit") |> render_click() =~
               "Edit U2ser"

      assert_patch(show_live, Routes.u2ser_show_path(conn, :edit, u2ser))

      assert show_live
             |> form("#u2ser-form", u2ser: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      {:ok, _, html} =
        show_live
        |> form("#u2ser-form", u2ser: @update_attrs)
        |> render_submit()
        |> follow_redirect(conn, Routes.u2ser_show_path(conn, :show, u2ser))

      assert html =~ "U2ser updated successfully"
      assert html =~ "some updated name"
    end
  end
end
