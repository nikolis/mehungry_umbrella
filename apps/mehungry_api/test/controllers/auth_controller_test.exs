defmodule MehungryApi.AuthControllerTest do
  use MehungryApi.ConnCase
  use ExUnit.Case

  import OpenApiSpex.TestAssertions

  alias Mehungry.Accounts

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "user authentication" do
    test "create user/ with valid attrs", %{conn: conn} do
      user_params = MehungryApi.Schemas.RegisterUserParams.schema().example

      conn = post(conn, Routes.auth_path(conn, :register_user, user_params))

      assert json_response(conn, 201)["data"]["email"] == user_params.user.email
      api_spec = MehungryApi.ApiSpec.spec()
      assert_schema(json_response(conn, 201), "RegisterUserResponse", api_spec)
    end

    test "login with user credentials", %{conn: conn} do
      api_spec = MehungryApi.ApiSpec.spec()
      user_params = MehungryApi.Schemas.LoginWithCredentialsParams.schema().example
      {:ok, user} = Accounts.register_user(user_params.credential)

      conn = post(conn, Routes.auth_path(conn, :login_with_credential, user_params))

      assert_schema(user_params, "LoginWithCredentialsParams", api_spec)
      assert Map.has_key?(json_response(conn, 200), "jwt") == true
      assert_schema(json_response(conn, 200), "LoginResponse", api_spec)
    end
  end
end
