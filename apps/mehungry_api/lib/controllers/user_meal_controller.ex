defmodule MehungryApi.UserMealController do
  use MehungryApi, :controller
  use OpenApiSpex.ControllerSpecs

  alias Mehungry.History
  alias Mehungry.History.UserMeal

  alias MehungryApi.Schemas.{
    UserMealListResponse,
    UserMealCreateParams,
    UserMealResponse,
    CreatedResponse,
    NoContent
  }

  action_fallback(MehungryApi.FallbackController)

  operation(:index,
    summary: "Index User Meals",
    responses: [
      ok: {"Recipe Search Response", "application/json", UserMealListResponse}
    ]
  )

  def index(conn, _params) do
    history_user_meals = History.list_history_user_meals()
    render(conn, "index.json", history_user_meals: history_user_meals)
  end

  operation(:create,
    summary: "Create UserMea",
    request_body: {"UserMeal params", "application/json", UserMealCreateParams},
    responses: [
      created: {"Created Response", "application/json", CreatedResponse}
    ]
  )

  def create(conn, %{"user_meal" => user_meal_params}) do
    with {:ok, %UserMeal{} = user_meal} <- History.create_user_meal(user_meal_params) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", Routes.user_meal_path(conn, :show, user_meal))
      |> render("show.json", user_meal: user_meal)
    end
  end

  operation(:show,
    summary: "Show User Meals",
    responses: [
      ok: {"User Meal Details", "application/json", UserMealResponse}
    ]
  )

  def show(conn, %{"id" => id}) do
    user_meal = History.get_user_meal!(id)
    render(conn, "show.json", user_meal: user_meal)
  end

  operation(:update,
    summary: "Update User meal",
    parameters: [
      id: [in: :path, type: :integer, description: "Recipe ID"]
    ],
    request_body: {"User Meal Params", "application/json", UserMealCreateParams},
    responses: [
      ok: {"Recipe Params", "application/json", UserMealResponse}
    ]
  )

  def update(conn, %{"id" => id, "user_meal" => user_meal_params}) do
    user_meal = History.get_user_meal!(id)

    with {:ok, %UserMeal{} = user_meal} <- History.update_user_meal(user_meal, user_meal_params) do
      render(conn, "show.json", user_meal: user_meal)
    end
  end

  operation(:delete,
    summary: "Delete UserMeal",
    parameters: [
      id: [in: :path, description: "UserMeal id", type: :integer, example: 1001]
    ],
    responses: [
      no_content: {"No Content", "application/json", NoContent}
    ]
  )

  def delete(conn, %{"id" => id}) do
    user_meal = History.get_user_meal!(id)

    with {:ok, %UserMeal{}} <- History.delete_user_meal(user_meal) do
      send_resp(conn, :no_content, "")
    end
  end
end
