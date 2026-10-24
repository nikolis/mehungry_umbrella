defmodule MehungryWeb.AnalyticsLiveTest do
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mehungry.AccountsFixtures

  alias Mehungry.Meta

  @admin_email Application.compile_env(:mehungry, :admin_email)

  setup %{conn: conn} do
    admin = user_fixture(%{email: @admin_email})
    %{conn: log_in_user(conn, admin)}
  end

  test "renders the anonymous-sessions panel with today's metrics", %{conn: conn} do
    # Seed a couple of recorded sessions for today.
    Meta.record_session(DateTime.utc_now(), 40)
    Meta.record_session(DateTime.utc_now(), 20)

    {:ok, _view, html} = live(conn, "/professional/analytics")

    assert html =~ "Anonymous sessions"
    assert html =~ "Sessions today"
    # 2 sessions recorded, average (40 + 20) / 2 = 30s.
    assert html =~ "Avg session"
    assert html =~ "30s"
  end
end
