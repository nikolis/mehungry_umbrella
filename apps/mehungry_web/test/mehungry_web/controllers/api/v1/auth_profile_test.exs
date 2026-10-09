defmodule MehungryWeb.Api.V1.AuthProfileTest do
  use MehungryWeb.ConnCase, async: true

  alias Mehungry.AccountsFixtures

  describe "POST /api/v1/auth/register" do
    test "creates a user and returns a bearer token", %{conn: conn} do
      email = AccountsFixtures.unique_user_email()

      conn =
        post(conn, ~p"/api/v1/auth/register", %{
          "email" => email,
          "password" => "super secret 12",
          "alias" => "Nikos"
        })

      assert %{"data" => %{"token" => token, "user" => user, "requires_confirmation" => true}} =
               json_response(conn, 201)

      assert is_binary(token)
      assert user["email"] == email
    end

    test "422 on invalid params", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/auth/register", %{"email" => "bad", "password" => "short"})
      assert %{"errors" => %{"fields" => fields}} = json_response(conn, 422)
      assert Map.has_key?(fields, "password") or Map.has_key?(fields, "email")
    end
  end

  describe "POST /api/v1/auth/login" do
    setup do
      password = AccountsFixtures.valid_user_password()
      user = AccountsFixtures.user_fixture(%{password: password})
      %{user: user, password: password}
    end

    test "returns a token for valid credentials", %{conn: conn, user: user, password: password} do
      conn = post(conn, ~p"/api/v1/auth/login", %{"email" => user.email, "password" => password})
      assert %{"data" => %{"token" => token}} = json_response(conn, 200)
      assert is_binary(token)
    end

    test "401 on bad credentials", %{conn: conn, user: user} do
      conn = post(conn, ~p"/api/v1/auth/login", %{"email" => user.email, "password" => "wrong"})
      assert json_response(conn, 401)
    end
  end

  describe "GET /api/v1/me" do
    setup :register_and_log_in_api_user

    test "returns the me snapshot", %{conn: conn, user: user} do
      conn = get(conn, ~p"/api/v1/me")

      assert %{
               "data" => %{
                 "id" => id,
                 "email" => email,
                 "tier" => "free",
                 "quota" => %{"recipe_generations" => %{"limit" => 0}},
                 "counts" => %{"followers" => 0}
               }
             } = json_response(conn, 200)

      assert id == user.id
      assert email == user.email
    end

    test "401 without a token", %{conn: _conn} do
      conn = get(Phoenix.ConnTest.build_conn(), ~p"/api/v1/me")
      assert json_response(conn, 401)
    end
  end

  describe "profile + preferences" do
    setup :register_and_log_in_api_user

    test "PUT /api/v1/me/profile updates fields", %{conn: conn} do
      conn =
        put(conn, ~p"/api/v1/me/profile", %{"alias" => "Chef", "daily_calorie_target" => 2200})

      assert %{"data" => %{"alias" => "Chef", "daily_calorie_target" => 2200}} =
               json_response(conn, 200)
    end

    test "PUT /api/v1/me/language switches language", %{conn: conn} do
      conn = put(conn, ~p"/api/v1/me/language", %{"lang" => "el"})
      assert %{"data" => %{"language_preference" => "el"}} = json_response(conn, 200)
    end

    test "preferences round-trip", %{conn: conn} do
      conn =
        put(conn, ~p"/api/v1/me/preferences", %{
          "diet" => "vegan",
          "intolerances" => ["lactose"],
          "onboarding_level" => 3
        })

      assert %{"data" => %{"diet" => "vegan", "intolerances" => ["lactose"], "onboarding_level" => 3}} =
               json_response(conn, 200)
    end

    test "GET /api/v1/preferences/options is public", %{conn: _conn} do
      conn = get(Phoenix.ConnTest.build_conn(), ~p"/api/v1/preferences/options")
      assert %{"data" => %{"diets" => diets, "languages" => _}} = json_response(conn, 200)
      assert is_list(diets)
    end
  end
end
