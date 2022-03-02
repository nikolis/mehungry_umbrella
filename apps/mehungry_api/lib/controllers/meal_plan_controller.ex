defmodule MehungryApi.MealPlanController do
  use MehungryApi, :controller

  alias Mehungry.Plans
  alias Mehungry.Plans.MealPlan

  action_fallback(MehungryApi.FallbackController)

  def index(conn, _params) do
    meal_plans = Plans.list_meal_plans()
    render(conn, "index.json", meal_plans: meal_plans)
  end

  def create(conn, %{"meal_plan" => meal_plan_params}) do
    with {:ok, %MealPlan{} = meal_plan} <- Plans.create_meal_plan(meal_plan_params) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", Routes.meal_plan_path(conn, :show, meal_plan))

      # |> render("show.json", meal_plan: meal_plan)
      send_resp(conn, :created, "")
    end
  end

  def show(conn, %{"id" => id}) do
    meal_plan = Plans.get_meal_plan!(id)
    render(conn, "show.json", meal_plan: meal_plan)
  end

  def update(conn, %{"id" => id, "meal_plan" => meal_plan_params}) do
    meal_plan = Plans.get_meal_plan!(id)

    with {:ok, %MealPlan{} = meal_plan} <- Plans.update_meal_plan(meal_plan, meal_plan_params) do
      render(conn, "show.json", meal_plan: meal_plan)
    end
  end

  def delete(conn, %{"id" => id}) do
    meal_plan = Plans.get_meal_plan!(id)

    with {:ok, %MealPlan{}} <- Plans.delete_meal_plan(meal_plan) do
      send_resp(conn, :no_content, "")
    end
  end
end
