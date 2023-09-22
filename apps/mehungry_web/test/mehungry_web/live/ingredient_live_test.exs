defmodule MehungryWeb.IngredientLiveTest do
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mehungry.FoodFixtures

  defp create_category(_) do
    category = category_fixture()
    %{category: category}
  end

  defp create_ingredient(_) do
    ingredient = ingredient_fixture()
    %{ingredient: ingredient}
  end

  defp create_measurement_unit(_) do
    measurement_unit = measurement_unit_fixture()
    %{measurement_unit: measurement_unit}
  end

  @create_attrs %{description: "some description", name: "some name", url: "some url"}
  @update_attrs %{
    description: "some updated description",
    name: "some updated name",
    url: "some updated url"
  }
  @invalid_attrs %{description: nil, name: nil, url: nil}

  describe "Index" do
    setup [
      :create_ingredient,
      :register_and_log_in_user,
      :create_category,
      :create_measurement_unit
    ]

    test "lists all ingredients", %{conn: conn, ingredient: ingredient} = _params do
      {:ok, _index_live, html} = live(conn, Routes.ingredient_index_path(conn, :index))

      assert html =~ "Listing Ingredients"
      assert html =~ ingredient.description
    end

    test "saves new ingredient", %{
      conn: conn,
      category: category,
      measurement_unit: measurement_unit
    } do
      {:ok, index_live, _html} = live(conn, Routes.ingredient_index_path(conn, :index))

      assert index_live |> element("a", "New Ingredient") |> render_click() =~
               "New Ingredient"

      assert_patch(index_live, Routes.ingredient_index_path(conn, :new))

      assert index_live
             |> form("#ingredient-form", ingredient: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      create_attrs =
        @create_attrs
        |> Enum.into(%{category_id: category.id, measurement_unit_id: measurement_unit.id})

      {:ok, _, html} =
        index_live
        |> form("#ingredient-form", ingredient: create_attrs)
        |> render_submit()
        |> follow_redirect(conn, Routes.ingredient_index_path(conn, :index))

      assert html =~ "Ingredient created successfully"
      assert html =~ "some name"
    end

    test "updates ingredient in listing", %{conn: conn, ingredient: ingredient} do
      {:ok, index_live, _html} = live(conn, Routes.ingredient_index_path(conn, :index))

      assert index_live |> element("#ingredient-#{ingredient.id} a", "Edit") |> render_click() =~
               "Edit Ingredient"

      assert_patch(index_live, Routes.ingredient_index_path(conn, :edit, ingredient))

      assert index_live
             |> form("#ingredient-form", ingredient: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      {:ok, _, html} =
        index_live
        |> form("#ingredient-form", ingredient: @update_attrs)
        |> render_submit()
        |> follow_redirect(conn, Routes.ingredient_index_path(conn, :index))

      assert html =~ "Ingredient updated successfully"
      assert html =~ "some updated description"
    end

    test "deletes ingredient in listing", %{conn: conn, ingredient: ingredient} do
      {:ok, index_live, _html} = live(conn, Routes.ingredient_index_path(conn, :index))

      assert index_live |> element("#ingredient-#{ingredient.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#ingredient-#{ingredient.id}")
    end
  end

  describe "Show" do
    setup [:create_ingredient, :register_and_log_in_user]

    test "displays ingredient", %{conn: conn, ingredient: ingredient} do
      {:ok, _show_live, html} = live(conn, Routes.ingredient_show_path(conn, :show, ingredient))

      assert html =~ "Show Ingredient"
      assert html =~ ingredient.description
    end

    test "updates ingredient within modal", %{conn: conn, ingredient: ingredient} do
      {:ok, show_live, _html} = live(conn, Routes.ingredient_show_path(conn, :show, ingredient))

      assert show_live |> element("a", "Edit") |> render_click() =~
               "Edit Ingredient"

      assert_patch(show_live, Routes.ingredient_show_path(conn, :edit, ingredient))

      assert show_live
             |> form("#ingredient-form", ingredient: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      {:ok, _, html} =
        show_live
        |> form("#ingredient-form", ingredient: @update_attrs)
        |> render_submit()
        |> follow_redirect(conn, Routes.ingredient_show_path(conn, :show, ingredient))

      assert html =~ "Ingredient updated successfully"
      assert html =~ "some updated description"
    end
  end
end
