defmodule MehungryWeb.Api.V1.NutritionistTest do
  use MehungryWeb.ConnCase, async: true

  alias Mehungry.AccountsFixtures

  setup :register_and_log_in_api_user

  describe "consumer invitations (/me/invitations)" do
    test "list, accept a pending invitation", %{conn: conn, user: user} do
      nutritionist = AccountsFixtures.user_fixture()
      {:ok, _inv} = Mehungry.Professionals.invite_client(nutritionist.id, user.email, "join me")

      listed = conn |> get(~p"/api/v1/me/invitations") |> json_response(200)
      assert %{"data" => [%{"id" => inv_id, "status" => "pending"} | _]} = listed

      accepted = conn |> post(~p"/api/v1/me/invitations/#{inv_id}/accept") |> json_response(200)
      assert %{"data" => %{"status" => "accepted"}} = accepted
    end
  end

  describe "nutritionist gate" do
    test "free-tier user is forbidden", %{conn: conn} do
      assert conn |> get(~p"/api/v1/nutritionist/clients") |> json_response(403)
    end

    test "pro-tier user can list clients", %{conn: conn, user: user} do
      {:ok, _} = Mehungry.Subscriptions.upsert_subscription(user.id, %{tier: "pro"})
      assert %{"data" => clients} = conn |> get(~p"/api/v1/nutritionist/clients") |> json_response(200)
      assert is_list(clients)
    end

    test "pro-tier invite surfaces client_not_found as 422", %{conn: conn, user: user} do
      {:ok, _} = Mehungry.Subscriptions.upsert_subscription(user.id, %{tier: "pro"})
      conn = post(conn, ~p"/api/v1/nutritionist/invitations", %{"email" => "nobody@nowhere.test"})
      assert json_response(conn, 422)
    end
  end
end
