defmodule MehungryWeb.CategoryLiveTest do
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mehungry.FoodFixtures

  @create_attrs %{description: "some description", name: "some name"}
  @update_attrs %{description: "some updated description", name: "some updated name"}
  @invalid_attrs %{description: nil, name: nil}

  defp create_category(_) do
    category = category_fixture()
    %{category: category}
  end

  describe "Index" do
    setup [:create_category, :register_and_log_in_user]

    test "lists all categories", %{conn: conn, category: category} do
      {:ok, _index_live, html} = live(conn, Routes.category_index_path(conn, :index))

      assert html =~ "Listing Categories"
      assert html =~ category.description
    end

    test "saves new category", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, Routes.category_index_path(conn, :index))

      assert index_live |> element("a", "New Category") |> render_click() =~
               "New Category"

      assert_patch(index_live, Routes.category_index_path(conn, :new))

      assert index_live
             |> form("#category-form", category: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      {:ok, _, html} =
        index_live
        |> form("#category-form", category: @create_attrs)
        |> render_submit()
        |> follow_redirect(conn, Routes.category_index_path(conn, :index))

      assert html =~ "Category created successfully"
      assert html =~ "some description"
    end

    test "updates category in listing", %{conn: conn, category: category} do
      {:ok, index_live, _html} = live(conn, Routes.category_index_path(conn, :index))

      assert index_live |> element("#category-#{category.id} a", "Edit") |> render_click() =~
               "Edit Category"

      assert_patch(index_live, Routes.category_index_path(conn, :edit, category))

      assert index_live
             |> form("#category-form", category: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      {:ok, _, html} =
        index_live
        |> form("#category-form", category: @update_attrs)
        |> render_submit()
        |> follow_redirect(conn, Routes.category_index_path(conn, :index))

      assert html =~ "Category updated successfully"
      assert html =~ "some updated description"
    end

    test "deletes category in listing", %{conn: conn, category: category} do
      {:ok, index_live, _html} = live(conn, Routes.category_index_path(conn, :index))

      assert index_live |> element("#category-#{category.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#category-#{category.id}")
    end
  end

  describe "Show" do
    setup [:create_category, :register_and_log_in_user]

    test "displays category", %{conn: conn, category: category} do
      {:ok, _show_live, html} = live(conn, Routes.category_show_path(conn, :show, category))

      assert html =~ "Show Category"
      assert html =~ category.description
    end

    test "updates category within modal", %{conn: conn, category: category} do
      {:ok, show_live, _html} = live(conn, Routes.category_show_path(conn, :show, category))

      assert show_live |> element("a", "Edit") |> render_click() =~
               "Edit Category"

      assert_patch(show_live, Routes.category_show_path(conn, :edit, category))

      assert show_live
             |> form("#category-form", category: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      {:ok, _, html} =
        show_live
        |> form("#category-form", category: @update_attrs)
        |> render_submit()
        |> follow_redirect(conn, Routes.category_show_path(conn, :show, category))

      assert html =~ "Category updated successfully"
      assert html =~ "some updated description"
    end
  end
end
