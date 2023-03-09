defmodule MehungryWeb.BedelLiveTest do
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mehungry.TobedelFixtures

  @create_attrs %{age: 42, url: "some url"}
  @update_attrs %{age: 43, url: "some updated url"}
  @invalid_attrs %{age: nil, url: nil}

  defp create_bedel(_) do
    bedel = bedel_fixture()
    %{bedel: bedel}
  end

  describe "Index" do
    setup [:create_bedel]

    test "lists all bedels", %{conn: conn, bedel: bedel} do
      {:ok, _index_live, html} = live(conn, Routes.bedel_index_path(conn, :index))

      assert html =~ "Listing Bedels"
      assert html =~ bedel.url
    end

    test "saves new bedel", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, Routes.bedel_index_path(conn, :index))

      assert index_live |> element("a", "New Bedel") |> render_click() =~
               "New Bedel"

      assert_patch(index_live, Routes.bedel_index_path(conn, :new))

      assert index_live
             |> form("#bedel-form", bedel: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      {:ok, _, html} =
        index_live
        |> form("#bedel-form", bedel: @create_attrs)
        |> render_submit()
        |> follow_redirect(conn, Routes.bedel_index_path(conn, :index))

      assert html =~ "Bedel created successfully"
      assert html =~ "some url"
    end

    test "updates bedel in listing", %{conn: conn, bedel: bedel} do
      {:ok, index_live, _html} = live(conn, Routes.bedel_index_path(conn, :index))

      assert index_live |> element("#bedel-#{bedel.id} a", "Edit") |> render_click() =~
               "Edit Bedel"

      assert_patch(index_live, Routes.bedel_index_path(conn, :edit, bedel))

      assert index_live
             |> form("#bedel-form", bedel: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      {:ok, _, html} =
        index_live
        |> form("#bedel-form", bedel: @update_attrs)
        |> render_submit()
        |> follow_redirect(conn, Routes.bedel_index_path(conn, :index))

      assert html =~ "Bedel updated successfully"
      assert html =~ "some updated url"
    end

    test "deletes bedel in listing", %{conn: conn, bedel: bedel} do
      {:ok, index_live, _html} = live(conn, Routes.bedel_index_path(conn, :index))

      assert index_live |> element("#bedel-#{bedel.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#bedel-#{bedel.id}")
    end
  end

  describe "Show" do
    setup [:create_bedel]

    test "displays bedel", %{conn: conn, bedel: bedel} do
      {:ok, _show_live, html} = live(conn, Routes.bedel_show_path(conn, :show, bedel))

      assert html =~ "Show Bedel"
      assert html =~ bedel.url
    end

    test "updates bedel within modal", %{conn: conn, bedel: bedel} do
      {:ok, show_live, _html} = live(conn, Routes.bedel_show_path(conn, :show, bedel))

      assert show_live |> element("a", "Edit") |> render_click() =~
               "Edit Bedel"

      assert_patch(show_live, Routes.bedel_show_path(conn, :edit, bedel))

      assert show_live
             |> form("#bedel-form", bedel: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      {:ok, _, html} =
        show_live
        |> form("#bedel-form", bedel: @update_attrs)
        |> render_submit()
        |> follow_redirect(conn, Routes.bedel_show_path(conn, :show, bedel))

      assert html =~ "Bedel updated successfully"
      assert html =~ "some updated url"
    end
  end
end
