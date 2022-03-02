defmodule MehungryApi.IngredientControllerTest do
  use MehungryApi.ConnCase
  use ExUnit.Case

  alias Mehungry.Accounts
  alias Mehungry.TestDataHelpers

  import OpenApiSpex.TestAssertions

  setup %{conn: conn} do
    user_params = MehungryApi.Schemas.RegisterUserParams.schema().example
    _user_resp = Accounts.register_user(user_params.user)
    login_params = MehungryApi.Schemas.LoginWithCredentialsParams.schema().example

    conn_login = build_conn()

    conn_login =
      post(conn_login, Routes.auth_path(conn_login, :login_with_credential, login_params))

    body_login_request = json_response(conn_login, 200)

    {:ok,
     conn: put_req_header(conn, "accept", "application/json"), jwt: body_login_request["jwt"]}
  end

  describe "user authentication" do
    test "search ingredient", %{conn: conn, jwt: jwt} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer " <> jwt)

      _ingredient = TestDataHelpers.ingredient_fixture(%{name: "Chicken"})
      api_spec = MehungryApi.ApiSpec.spec()
      ingredient_search_params = MehungryApi.Schemas.IngredientSearchParams.schema().example

      conn =
        get(
          conn,
          Routes.ingredient_path(
            conn,
            :search,
            ingredient_search_params.name,
            ingredient_search_params.language
          )
        )

      assert Enum.count(json_response(conn, 200)["data"]) == 1
      assert_schema(json_response(conn, 200), "IngredientSearchResponse", api_spec)
    end
  end
end
