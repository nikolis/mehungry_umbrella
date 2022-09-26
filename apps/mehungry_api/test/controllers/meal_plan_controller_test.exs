defmodule MehungryApi.MealPlanControllerTest do
  use MehungryApi.ConnCase

  """
  alias Mehungry.Plans
  alias Mehungry.Plans.MealPlan

  @create_attrs %{
    description: "some description",
    title: "some title"
  }
  @update_attrs %{
    description: "some updated description",
    title: "some updated title"
  }
  @invalid_attrs %{description: nil, title: nil}

  def fixture(:meal_plan) do
    {:ok, meal_plan} = Plans.create_meal_plan(@create_attrs)
    meal_plan
  end

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "index" do
    test "lists all meal_plans", %{conn: conn} do
      conn = get(conn, Routes.meal_plan_path(conn, :index))
      assert json_response(conn, 200)["data"] == []
    end
  end

  describe "create meal_plan" do
    test "renders meal_plan when data is valid", %{conn: conn} do
      conn = post(conn, Routes.meal_plan_path(conn, :create), meal_plan: @create_attrs)
      assert %{"id" => id} = json_response(conn, 201)["data"]

      conn = get(conn, Routes.meal_plan_path(conn, :show, id))

      assert %{
               "id" => id,
               "description" => "some description",
               "title" => "some title"
             } = json_response(conn, 200)["data"]
    end

    test "renders errors when data is invalid", %{conn: conn} do
      conn = post(conn, Routes.meal_plan_path(conn, :create), meal_plan: @invalid_attrs)
      assert json_response(conn, 422)["errors"] != %{}
    end
  end

  describe "update meal_plan" do
    setup [:create_meal_plan]

    test "renders meal_plan when data is valid", %{conn: conn, meal_plan: %MealPlan{id: id} = meal_plan} do
      conn = put(conn, Routes.meal_plan_path(conn, :update, meal_plan), meal_plan: @update_attrs)
      assert %{"id" => ^id} = json_response(conn, 200)["data"]

      conn = get(conn, Routes.meal_plan_path(conn, :show, id))

      assert %{
               "id" => id,
               "description" => "some updated description",
               "title" => "some updated title"
             } = json_response(conn, 200)["data"]
    end

    test "renders errors when data is invalid", %{conn: conn, meal_plan: meal_plan} do
      conn = put(conn, Routes.meal_plan_path(conn, :update, meal_plan), meal_plan: @invalid_attrs)
      assert json_response(conn, 422)["errors"] != %{}
    end
  end

  describe "delete meal_plan" do
    setup [:create_meal_plan]

    test "deletes chosen meal_plan", %{conn: conn, meal_plan: meal_plan} do
      conn = delete(conn, Routes.meal_plan_path(conn, :delete, meal_plan))
      assert response(conn, 204)

      assert_error_sent 404, fn ->
        get(conn, Routes.meal_plan_path(conn, :show, meal_plan))
      end
    end
  end

  defp create_meal_plan(_) do
    meal_plan = fixture(:meal_plan)
    {:ok, meal_plan: meal_plan}
    end
  """
end
