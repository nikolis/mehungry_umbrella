defmodule MehungryApi.DailyMealPlanController do
  use MehungryApi, :controller

  alias Mehungry.Plans
  alias Mehungry.Plans.DailyMealPlan

  action_fallback(MehungryApi.FallbackController)

  def index(conn, _params) do
    daily_meal_plans = Plans.list_daily_meal_plans()
    render(conn, "index.json", daily_meal_plans: daily_meal_plans)
  end

  def create(conn, %{"daily_meal_plan" => daily_meal_plan_params}) do
    with {:ok, %DailyMealPlan{} = daily_meal_plan} <-
           Plans.create_daily_meal_plan(daily_meal_plan_params) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", Routes.daily_meal_plan_path(conn, :show, daily_meal_plan))
      |> render("show.json", daily_meal_plan: daily_meal_plan)
    end
  end

  def show(conn, %{"id" => id}) do
    daily_meal_plan = Plans.get_daily_meal_plan!(id)
    render(conn, "show.json", daily_meal_plan: daily_meal_plan)
  end

  def update(conn, %{"id" => id, "daily_meal_plan" => daily_meal_plan_params}) do
    daily_meal_plan = Plans.get_daily_meal_plan!(id)

    with {:ok, %DailyMealPlan{} = daily_meal_plan} <-
           Plans.update_daily_meal_plan(daily_meal_plan, daily_meal_plan_params) do
      render(conn, "show.json", daily_meal_plan: daily_meal_plan)
    end
  end

  def delete(conn, %{"id" => id}) do
    daily_meal_plan = Plans.get_daily_meal_plan!(id)

    with {:ok, %DailyMealPlan{}} <- Plans.delete_daily_meal_plan(daily_meal_plan) do
      send_resp(conn, :no_content, "")
    end
  end
end
