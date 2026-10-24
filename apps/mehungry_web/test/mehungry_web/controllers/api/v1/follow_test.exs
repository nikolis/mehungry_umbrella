defmodule MehungryWeb.Api.V1.FollowTest do
  use MehungryWeb.ConnCase, async: true

  alias Mehungry.Accounts.UserContent
  alias Mehungry.AccountsFixtures

  setup :register_and_log_in_api_user

  test "follow then unfollow a user", %{conn: conn, user: me} do
    target = AccountsFixtures.user_fixture()

    assert %{"data" => %{"following" => true, "followers_count" => 1}} =
             conn |> post(~p"/api/v1/users/#{target.id}/follow") |> json_response(200)

    assert UserContent.following?(me.id, target.id)

    assert %{"data" => %{"following" => false, "followers_count" => 0}} =
             conn |> delete(~p"/api/v1/users/#{target.id}/follow") |> json_response(200)

    refute UserContent.following?(me.id, target.id)
  end

  test "following is idempotent (no duplicate rows / inflated count)", %{conn: conn} do
    target = AccountsFixtures.user_fixture()

    conn |> post(~p"/api/v1/users/#{target.id}/follow") |> json_response(200)

    assert %{"data" => %{"followers_count" => 1}} =
             conn |> post(~p"/api/v1/users/#{target.id}/follow") |> json_response(200)
  end

  test "cannot follow yourself", %{conn: conn, user: me} do
    assert %{"errors" => _} =
             conn |> post(~p"/api/v1/users/#{me.id}/follow") |> json_response(422)
  end

  test "GET /users/:id reflects the viewer's follow state", %{conn: conn} do
    target = AccountsFixtures.user_fixture()

    assert %{"data" => %{"following" => false}} =
             conn |> get(~p"/api/v1/users/#{target.id}") |> json_response(200)

    conn |> post(~p"/api/v1/users/#{target.id}/follow") |> json_response(200)

    assert %{"data" => %{"following" => true}} =
             conn |> get(~p"/api/v1/users/#{target.id}") |> json_response(200)
  end

  test "GET /users/:id following is false for anonymous viewers", %{conn: conn} do
    target = AccountsFixtures.user_fixture()
    anon = Phoenix.ConnTest.build_conn()

    assert %{"data" => %{"following" => false}} =
             anon |> get(~p"/api/v1/users/#{target.id}") |> json_response(200)

    # Sanity: the authenticated conn from setup also sees false before following.
    assert %{"data" => %{"following" => false}} =
             conn |> get(~p"/api/v1/users/#{target.id}") |> json_response(200)
  end
end
