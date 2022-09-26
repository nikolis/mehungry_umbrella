defmodule MehungryApi.UserMealControllerTest do
  use MehungryApi.ConnCase

  import Mehungry.HistoryFixtures
  import OpenApiSpex.TestAssertions

  alias Mehungry.History.UserMeal
  alias Mehungry.Accounts
  alias Mehungry.TestDataHelpers
  alias Mehungry.Food

  @create_attrs %{
    meal_datetime: "2019-01-01T00:00:00.000+00:00",
    title: "some title"
  }
  @update_attrs %{
    meal_datetime: ~U[2022-02-14 16:50:00Z],
    title: "some updated title"
  }
  @invalid_attrs %{meal_datetime: nil, title: nil}

  def fixture(:recipe, title \\ "test1") do
    mu = TestDataHelpers.measurement_unit_fixture()
    ingredient = TestDataHelpers.ingredient_fixture(%{name: title})
    recipe_params = MehungryApi.Schemas.Recipe.schema().example

    valid_attrs =
      Map.put(recipe_params, "recipe_ingredients", [
        %{
          "quantity" => 20,
          "measurement_unit_id" => mu.id,
          "ingredient_id" => ingredient.id,
          "ingredient_allias" => "Pork"
        },
        %{"quantity" => 30, "measurement_unit_id" => mu.id, "ingredient_id" => ingredient.id}
      ])

    valid_attrs = Map.put(valid_attrs, "title", title)

    result = Food.create_recipe(valid_attrs)

    {:ok, recipe} = result
    recipe
  end

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}

    user_params = MehungryApi.Schemas.RegisterUserParams.schema().example
    user_resp = Accounts.register_user(user_params.user)
    login_params = MehungryApi.Schemas.LoginWithCredentialsParams.schema().example

    conn_login = build_conn()

    conn_login =
      post(conn_login, Routes.auth_path(conn_login, :login_with_credential, login_params))

    body_login_request = json_response(conn_login, 200)
    jwt = body_login_request["jwt"]

    conn =
      conn
      |> put_req_header("authorization", "Bearer " <> jwt)

    %{conn: conn, user: user_resp}
  end

  describe "index" do
    test "lists all history_user_meals", %{conn: conn} do
      {:ok, recipe: recipe, recipe_2: recipe_2} = create_recipe()

      create_attrs =
        @create_attrs
        |> Map.put(:recipe_user_meals, [%{recipe_id: recipe.id}, %{recipe_id: recipe_2.id}])

      conn = post(conn, Routes.user_meal_path(conn, :create), user_meal: create_attrs)

      conn = get(conn, Routes.user_meal_path(conn, :index))
      assert Enum.count(json_response(conn, 200)["data"]) == 1

      api_spec = MehungryApi.ApiSpec.spec()
      [data] = json_response(conn, 200)["data"]
      recipes = List.first(data["recipes"])
      IO.inspect(recipes["recipe_ingredients"])
      assert_schema(json_response(conn, 200), "UserMealListResponse", api_spec)
    end
  end

  describe "create user_meal" do
    test "renders user_meal when data is valid", %{conn: conn} do
      {:ok, recipe: recipe, recipe_2: recipe_2} = create_recipe()

      create_attrs =
        @create_attrs
        |> Map.put(:recipe_user_meals, [%{recipe_id: recipe.id}, %{recipe_id: recipe_2.id}])

      conn = post(conn, Routes.user_meal_path(conn, :create), user_meal: create_attrs)
      assert %{"id" => id} = json_response(conn, 201)["data"]

      conn = get(conn, Routes.user_meal_path(conn, :show, id))

      api_spec = MehungryApi.ApiSpec.spec()

      assert %{
               "id" => ^id,
               "meal_datetime" => "2019-01-01T00:00:00Z",
               "title" => "some title"
             } = json_response(conn, 200)["data"]

      assert_schema(json_response(conn, 200), "CreatedResponse", api_spec)
    end

    test "renders errors when data is invalid", %{conn: conn} do
      conn = post(conn, Routes.user_meal_path(conn, :create), user_meal: @invalid_attrs)
      assert json_response(conn, 422)["errors"] != %{}
    end
  end

  describe "update user_meal" do
    setup [:create_user_meal]

    test "renders user_meal when data is valid", %{
      conn: conn,
      user_meal: %UserMeal{id: id} = user_meal
    } do
      conn = put(conn, Routes.user_meal_path(conn, :update, user_meal), user_meal: @update_attrs)
      assert %{"id" => ^id} = json_response(conn, 200)["data"]

      conn = get(conn, Routes.user_meal_path(conn, :show, id))

      assert %{
               "id" => ^id,
               "meal_datetime" => "2022-02-14T16:50:00Z",
               "title" => "some updated title"
             } = json_response(conn, 200)["data"]
    end

    test "renders errors when data is invalid", %{conn: conn, user_meal: user_meal} do
      conn = put(conn, Routes.user_meal_path(conn, :update, user_meal), user_meal: @invalid_attrs)
      assert json_response(conn, 422)["errors"] != %{}
    end
  end

  describe "delete user_meal" do
    setup [:create_user_meal]

    test "deletes chosen user_meal", %{conn: conn, user_meal: user_meal} do
      conn = delete(conn, Routes.user_meal_path(conn, :delete, user_meal))
      assert response(conn, 204)

      assert_error_sent(404, fn ->
        get(conn, Routes.user_meal_path(conn, :show, user_meal))
      end)
    end
  end

  defp create_user_meal(_) do
    user_meal = user_meal_fixture()
    %{user_meal: user_meal}
  end

  defp create_recipe() do
    recipe_0 = fixture(:recipe, "other_name")
    recipe = fixture(:recipe)
    {:ok, recipe: recipe_0, recipe_2: recipe}
  end
end
