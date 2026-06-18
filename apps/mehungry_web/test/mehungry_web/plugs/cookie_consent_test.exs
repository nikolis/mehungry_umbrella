defmodule MehungryWeb.Plugs.CookieConsentTest do
  use MehungryWeb.ConnCase, async: true

  alias MehungryWeb.Plugs.CookieConsent

  describe "call/2" do
    test "assigns :pending when cookie is absent" do
      conn =
        build_conn()
        |> init_test_session(%{})
        |> CookieConsent.call([])

      assert conn.assigns[:cookie_consent] == :pending
      assert get_session(conn, "cookie_consent") == "pending"
    end

    test "assigns :accepted and writes session after Accept POST + recycle" do
      conn1 =
        build_conn()
        |> post("/cookie-consent/accept")

      conn2 =
        conn1
        |> recycle()
        |> get("/welcome")

      assert conn2.assigns[:cookie_consent] == :accepted
      assert get_session(conn2, "cookie_consent") == "accepted"
    end

    test "assigns :declined and writes session after Decline POST + recycle" do
      conn1 =
        build_conn()
        |> post("/cookie-consent/decline")

      conn2 =
        conn1
        |> recycle()
        |> get("/welcome")

      assert conn2.assigns[:cookie_consent] == :declined
      assert get_session(conn2, "cookie_consent") == "declined"
    end
  end
end
