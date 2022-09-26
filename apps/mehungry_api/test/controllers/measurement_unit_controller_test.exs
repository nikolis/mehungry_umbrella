defmodule MehungryApi.MeasurementUnitControllerTest do
  use MehungryApi.ConnCase

  """
  alias Mehungry.Food
  alias Mehungry.Food.MeasurementUnit

  @create_attrs %{
    name: "some name",
    url: "some url"
  }
  @update_attrs %{
    name: "some updated name",
    url: "some updated url"
  }
  @invalid_attrs %{name: nil, url: nil}

  def fixture(:measurement_unit) do
    {:ok, measurement_unit} = Food.create_measurement_unit(@create_attrs)
    measurement_unit
  end

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "index" do
    test "lists all measurement_units", %{conn: conn} do
      conn = get(conn, Routes.measurement_unit_path(conn, :index))
      assert json_response(conn, 200)["data"] == []
    end
  end

  describe "create measurement_unit" do
    test "renders measurement_unit when data is valid", %{conn: conn} do
      conn = post(conn, Routes.measurement_unit_path(conn, :create), measurement_unit: @create_attrs)
      assert %{"id" => id} = json_response(conn, 201)["data"]

      conn = get(conn, Routes.measurement_unit_path(conn, :show, id))

      assert %{
               "id" => id,
               "name" => "some name",
               "url" => "some url"
             } = json_response(conn, 200)["data"]
    end

    test "renders errors when data is invalid", %{conn: conn} do
      conn = post(conn, Routes.measurement_unit_path(conn, :create), measurement_unit: @invalid_attrs)
      assert json_response(conn, 422)["errors"] != %{}
    end
  end

  describe "update measurement_unit" do
    setup [:create_measurement_unit]

    test "renders measurement_unit when data is valid", %{conn: conn, measurement_unit: %MeasurementUnit{id: id} = measurement_unit} do
      conn = put(conn, Routes.measurement_unit_path(conn, :update, measurement_unit), measurement_unit: @update_attrs)
      assert %{"id" => ^id} = json_response(conn, 200)["data"]

      conn = get(conn, Routes.measurement_unit_path(conn, :show, id))

      assert %{
               "id" => id,
               "name" => "some updated name",
               "url" => "some updated url"
             } = json_response(conn, 200)["data"]
    end

    test "renders errors when data is invalid", %{conn: conn, measurement_unit: measurement_unit} do
      conn = put(conn, Routes.measurement_unit_path(conn, :update, measurement_unit), measurement_unit: @invalid_attrs)
      assert json_response(conn, 422)["errors"] != %{}
    end
  end

  describe "delete measurement_unit" do
    setup [:create_measurement_unit]

    test "deletes chosen measurement_unit", %{conn: conn, measurement_unit: measurement_unit} do
      conn = delete(conn, Routes.measurement_unit_path(conn, :delete, measurement_unit))
      assert response(conn, 204)

      assert_error_sent 404, fn ->
        get(conn, Routes.measurement_unit_path(conn, :show, measurement_unit))
      end
    end
  end

  defp create_measurement_unit(_) do
    measurement_unit = fixture(:measurement_unit)
    {:ok, measurement_unit: measurement_unit}
    end
  """
end
