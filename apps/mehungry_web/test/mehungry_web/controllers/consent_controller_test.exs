defmodule MehungryWeb.ConsentControllerTest do
  use MehungryWeb.ConnCase, async: true

  describe "POST /cookie-consent/accept" do
    test "sets signed cookie_consent=accepted and redirects to /" do
      conn = post(build_conn(), "/cookie-consent/accept")

      assert redirected_to(conn) == "/"
      cookie = conn.resp_cookies["cookie_consent"]
      assert is_binary(cookie[:value])
      assert cookie[:max_age] == 31_536_000
    end

    test "redirects to Referer when present" do
      conn =
        build_conn()
        |> put_req_header("referer", "/browse")
        |> post("/cookie-consent/accept")

      assert redirected_to(conn) == "/browse"
    end
  end

  describe "POST /cookie-consent/decline" do
    test "sets signed cookie_consent=declined and redirects to /" do
      conn = post(build_conn(), "/cookie-consent/decline")

      assert redirected_to(conn) == "/"
      cookie = conn.resp_cookies["cookie_consent"]
      assert is_binary(cookie[:value])
      assert cookie[:max_age] == 31_536_000
    end
  end

  describe "cookie persists across requests" do
    test "assign is :accepted on next request after accept" do
      conn1 = post(build_conn(), "/cookie-consent/accept")
      conn2 = recycle(conn1) |> get("/welcome")

      assert conn2.assigns[:cookie_consent] == :accepted
    end

    test "assign is :declined on next request after decline" do
      conn1 = post(build_conn(), "/cookie-consent/decline")
      conn2 = recycle(conn1) |> get("/welcome")

      assert conn2.assigns[:cookie_consent] == :declined
    end
  end
end
