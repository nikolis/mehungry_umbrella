defmodule MehungryApi.MealControllerTest do
  use MehungryApi.ConnCase

  alias Mehungry.Plans
  alias Mehungry.Plans.Meal

  """
  @create_attrs %{
  meal_note: "some meal_note",
  meal_title: "some meal_title"
  }
  @update_attrs %{
  meal_note: "some updated meal_note",
  meal_title: "some updated meal_title"
  }
  @invalid_attrs %{meal_note: nil, meal_title: nil}

  def fixture(:meal) do
  {:ok, meal} = Plans.create_meal(@create_attrs)
  meal
  end

  setup %{conn: conn} do
  {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "index" do
  test "lists all meals", %{conn: conn} do
    conn = get(conn, Routes.meal_path(conn, :index))
    assert json_response(conn, 200)["data"] == []
  end
  end

  describe "create meal" do
  test "renders meal when data is valid", %{conn: conn} do
    conn = post(conn, Routes.meal_path(conn, :create), meal: @create_attrs)
    assert %{"id" => id} = json_response(conn, 201)["data"]

    conn = get(conn, Routes.meal_path(conn, :show, id))

    assert %{
             "id" => id,
             "meal_note" => "some meal_note",
             "meal_title" => "some meal_title"
           } = json_response(conn, 200)["data"]
  end

  test "renders errors when data is invalid", %{conn: conn} do
    conn = post(conn, Routes.meal_path(conn, :create), meal: @invalid_attrs)
    assert json_response(conn, 422)["errors"] != %{}
  end
  end

  describe "update meal" do
  setup [:create_meal]

  test "renders meal when data is valid", %{conn: conn, meal: %Meal{id: id} = meal} do
    conn = put(conn, Routes.meal_path(conn, :update, meal), meal: @update_attrs)
    assert %{"id" => ^id} = json_response(conn, 200)["data"]

    conn = get(conn, Routes.meal_path(conn, :show, id))

    assert %{
             "id" => id,
             "meal_note" => "some updated meal_note",
             "meal_title" => "some updated meal_title"
           } = json_response(conn, 200)["data"]
  end

  test "renders errors when data is invalid", %{conn: conn, meal: meal} do
    conn = put(conn, Routes.meal_path(conn, :update, meal), meal: @invalid_attrs)
    assert json_response(conn, 422)["errors"] != %{}
  end
  end

  describe "delete meal" do
  setup [:create_meal]

  test "deletes chosen meal", %{conn: conn, meal: meal} do
    conn = delete(conn, Routes.meal_path(conn, :delete, meal))
    assert response(conn, 204)

    assert_error_sent 404, fn ->
      get(conn, Routes.meal_path(conn, :show, meal))
    end
  end
  end

  defp create_meal(_) do
  meal = fixture(:meal)
  {:ok, meal: meal}
  end
  """
end
