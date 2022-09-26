defmodule MehungryWeb.DeleteTestLiveTest do
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mehungry.TestDeleteFixtures

  @create_attrs %{name: "some name"}
  @update_attrs %{name: "some updated name"}
  @invalid_attrs %{name: nil}

  defp create_delete_test(_) do
    delete_test = delete_test_fixture()
    %{delete_test: delete_test}
  end

  describe "Index" do
    setup [:create_delete_test]

    test "lists all deletes", %{conn: conn, delete_test: delete_test} do
      {:ok, _index_live, html} = live(conn, Routes.delete_test_index_path(conn, :index))

      assert html =~ "Listing Deletes"
      assert html =~ delete_test.name
    end

    test "saves new delete_test", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, Routes.delete_test_index_path(conn, :index))

      assert index_live |> element("a", "New Delete test") |> render_click() =~
               "New Delete test"

      assert_patch(index_live, Routes.delete_test_index_path(conn, :new))

      assert index_live
             |> form("#delete_test-form", delete_test: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      {:ok, _, html} =
        index_live
        |> form("#delete_test-form", delete_test: @create_attrs)
        |> render_submit()
        |> follow_redirect(conn, Routes.delete_test_index_path(conn, :index))

      assert html =~ "Delete test created successfully"
      assert html =~ "some name"
    end

    test "updates delete_test in listing", %{conn: conn, delete_test: delete_test} do
      {:ok, index_live, _html} = live(conn, Routes.delete_test_index_path(conn, :index))

      assert index_live |> element("#delete_test-#{delete_test.id} a", "Edit") |> render_click() =~
               "Edit Delete test"

      assert_patch(index_live, Routes.delete_test_index_path(conn, :edit, delete_test))

      assert index_live
             |> form("#delete_test-form", delete_test: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      {:ok, _, html} =
        index_live
        |> form("#delete_test-form", delete_test: @update_attrs)
        |> render_submit()
        |> follow_redirect(conn, Routes.delete_test_index_path(conn, :index))

      assert html =~ "Delete test updated successfully"
      assert html =~ "some updated name"
    end

    test "deletes delete_test in listing", %{conn: conn, delete_test: delete_test} do
      {:ok, index_live, _html} = live(conn, Routes.delete_test_index_path(conn, :index))

      assert index_live |> element("#delete_test-#{delete_test.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#delete_test-#{delete_test.id}")
    end
  end

  describe "Show" do
    setup [:create_delete_test]

    test "displays delete_test", %{conn: conn, delete_test: delete_test} do
      {:ok, _show_live, html} = live(conn, Routes.delete_test_show_path(conn, :show, delete_test))

      assert html =~ "Show Delete test"
      assert html =~ delete_test.name
    end

    test "updates delete_test within modal", %{conn: conn, delete_test: delete_test} do
      {:ok, show_live, _html} = live(conn, Routes.delete_test_show_path(conn, :show, delete_test))

      assert show_live |> element("a", "Edit") |> render_click() =~
               "Edit Delete test"

      assert_patch(show_live, Routes.delete_test_show_path(conn, :edit, delete_test))

      assert show_live
             |> form("#delete_test-form", delete_test: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      {:ok, _, html} =
        show_live
        |> form("#delete_test-form", delete_test: @update_attrs)
        |> render_submit()
        |> follow_redirect(conn, Routes.delete_test_show_path(conn, :show, delete_test))

      assert html =~ "Delete test updated successfully"
      assert html =~ "some updated name"
    end
  end
end
