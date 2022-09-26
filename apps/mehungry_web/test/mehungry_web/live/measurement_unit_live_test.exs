defmodule MehungryWeb.MeasurementUnitLiveTest do
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mehungry.FoodFixtures

  @create_attrs %{name: "some name", url: "some url"}
  @update_attrs %{name: "some updated name", url: "some updated url"}
  @invalid_attrs %{name: nil, url: nil}

  defp create_measurement_unit(_) do
    measurement_unit = measurement_unit_fixture()
    %{measurement_unit: measurement_unit}
  end

  describe "Index" do
    setup [:create_measurement_unit]

    test "lists all measurement_units", %{conn: conn, measurement_unit: measurement_unit} do
      {:ok, _index_live, html} = live(conn, Routes.measurement_unit_index_path(conn, :index))

      assert html =~ "Listing Measurement units"
      assert html =~ measurement_unit.name
    end

    test "saves new measurement_unit", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, Routes.measurement_unit_index_path(conn, :index))

      assert index_live |> element("a", "New Measurement unit") |> render_click() =~
               "New Measurement unit"

      assert_patch(index_live, Routes.measurement_unit_index_path(conn, :new))

      assert index_live
             |> form("#measurement_unit-form", measurement_unit: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      {:ok, _, html} =
        index_live
        |> form("#measurement_unit-form", measurement_unit: @create_attrs)
        |> render_submit()
        |> follow_redirect(conn, Routes.measurement_unit_index_path(conn, :index))

      assert html =~ "Measurement unit created successfully"
      assert html =~ "some name"
    end

    test "updates measurement_unit in listing", %{conn: conn, measurement_unit: measurement_unit} do
      {:ok, index_live, _html} = live(conn, Routes.measurement_unit_index_path(conn, :index))

      assert index_live
             |> element("#measurement_unit-#{measurement_unit.id} a", "Edit")
             |> render_click() =~
               "Edit Measurement unit"

      assert_patch(index_live, Routes.measurement_unit_index_path(conn, :edit, measurement_unit))

      assert index_live
             |> form("#measurement_unit-form", measurement_unit: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      {:ok, _, html} =
        index_live
        |> form("#measurement_unit-form", measurement_unit: @update_attrs)
        |> render_submit()
        |> follow_redirect(conn, Routes.measurement_unit_index_path(conn, :index))

      assert html =~ "Measurement unit updated successfully"
      assert html =~ "some updated name"
    end

    test "deletes measurement_unit in listing", %{conn: conn, measurement_unit: measurement_unit} do
      {:ok, index_live, _html} = live(conn, Routes.measurement_unit_index_path(conn, :index))

      assert index_live
             |> element("#measurement_unit-#{measurement_unit.id} a", "Delete")
             |> render_click()

      refute has_element?(index_live, "#measurement_unit-#{measurement_unit.id}")
    end
  end

  describe "Show" do
    setup [:create_measurement_unit]

    test "displays measurement_unit", %{conn: conn, measurement_unit: measurement_unit} do
      {:ok, _show_live, html} =
        live(conn, Routes.measurement_unit_show_path(conn, :show, measurement_unit))

      assert html =~ "Show Measurement unit"
      assert html =~ measurement_unit.name
    end

    test "updates measurement_unit within modal", %{
      conn: conn,
      measurement_unit: measurement_unit
    } do
      {:ok, show_live, _html} =
        live(conn, Routes.measurement_unit_show_path(conn, :show, measurement_unit))

      assert show_live |> element("a", "Edit") |> render_click() =~
               "Edit Measurement unit"

      assert_patch(show_live, Routes.measurement_unit_show_path(conn, :edit, measurement_unit))

      assert show_live
             |> form("#measurement_unit-form", measurement_unit: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      {:ok, _, html} =
        show_live
        |> form("#measurement_unit-form", measurement_unit: @update_attrs)
        |> render_submit()
        |> follow_redirect(conn, Routes.measurement_unit_show_path(conn, :show, measurement_unit))

      assert html =~ "Measurement unit updated successfully"
      assert html =~ "some updated name"
    end
  end
end
