defmodule MehungryWeb.UpgradeLiveTest do
  @moduledoc false

  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest
  alias Mehungry.Subscriptions

  setup [:register_and_log_in_user]

  test "pro (nutritionist) users do not see Mehungry Plus subscribe buttons", %{
    conn: conn,
    user: user
  } do
    {:ok, _sub} =
      Subscriptions.upsert_subscription(user.id, %{
        tier: "pro",
        status: "active"
      })

    {:ok, _index_live, html} = live(conn, "/upgrade")

    assert html =~ "Included in your Pro plan"
    refute html =~ "Subscribe monthly — "
  end

  test "pro users cannot trigger the subscribe event for Mehungry Plus", %{
    conn: conn,
    user: user
  } do
    {:ok, _sub} =
      Subscriptions.upsert_subscription(user.id, %{
        tier: "pro",
        status: "active"
      })

    {:ok, index_live, _html} = live(conn, "/upgrade")

    html =
      index_live
      |> render_hook("subscribe", %{"interval" => "monthly"})

    assert html =~ "Your Pro plan already includes everything in Mehungry Plus."
  end

  test "free users see Mehungry Plus subscribe buttons", %{conn: conn} do
    {:ok, _index_live, html} = live(conn, "/upgrade")

    assert html =~ "Subscribe monthly — "
    refute html =~ "Included in your Pro plan"
  end
end
