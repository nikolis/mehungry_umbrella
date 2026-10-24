defmodule MehungryWeb.Api.V1.SubscriptionTest do
  use MehungryWeb.ConnCase, async: true

  setup :register_and_log_in_api_user

  test "GET /subscription returns tier, plans and quota", %{conn: conn} do
    conn = get(conn, ~p"/api/v1/subscription")

    assert %{"data" => %{"tier" => "free", "plans" => plans, "quota" => quota}} =
             json_response(conn, 200)

    assert is_list(plans)
    assert Enum.any?(plans, &(&1["key"] == "m3hungry_plus"))
    assert %{"recipe_generations" => %{"limit" => 0}} = quota
  end

  test "checkout 400s when Stripe is not configured", %{conn: conn} do
    conn = post(conn, ~p"/api/v1/subscription/checkout", %{"plan" => "m3hungry_plus", "interval" => "monthly"})
    assert json_response(conn, 400)
  end

  test "portal 403s without a Stripe customer", %{conn: conn} do
    conn = post(conn, ~p"/api/v1/subscription/portal")
    assert json_response(conn, 403)
  end
end
