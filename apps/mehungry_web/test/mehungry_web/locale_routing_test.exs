defmodule MehungryWeb.LocaleRoutingTest do
  use MehungryWeb.ConnCase, async: true

  describe "locale-prefixed routing" do
    test "bare / redirects an anonymous visitor to the default-locale welcome page", %{conn: conn} do
      conn = get(conn, "/")
      assert redirected_to(conn) == "/en/welcome"
    end

    test "a supported locale prefix serves the page and sets the session locale", %{conn: conn} do
      conn = get(conn, "/el/welcome")
      assert html_response(conn, 200)
      assert get_session(conn, "locale") == "el"
      assert conn.assigns[:locale] == "el"
    end

    test "an unsupported locale prefix redirects to the detected default", %{conn: conn} do
      conn = get(conn, "/xx/welcome")
      assert redirected_to(conn) == "/en/welcome"
    end

    test "the bare unprefixed page still resolves", %{conn: conn} do
      conn = get(conn, "/welcome")
      assert html_response(conn, 200)
    end

    test "a localized content page renders localized chrome, html lang, and hreflang", %{
      conn: conn
    } do
      conn = get(conn, "/el/browse")
      html = html_response(conn, 200)
      # <html lang="el"> from the root layout
      assert html =~ ~s(lang="el")
      # Greek menu label from the Gettext-backed chrome
      assert html =~ "Περιήγηση"
      # hreflang alternates in <head>
      assert html =~ ~s(hreflang="el")
      assert html =~ ~s(hreflang="x-default")
    end
  end

  describe "language switch" do
    test "swaps the locale segment of the referring page for an anonymous visitor", %{conn: conn} do
      conn =
        conn
        |> put_req_header("referer", "http://localhost/en/foods/tomato")
        |> get("/users/language/el")

      assert redirected_to(conn) == "/el/foods/tomato"
      assert get_session(conn, "locale") == "el"
    end

    test "falls back to the localized home when there is no referer", %{conn: conn} do
      conn = get(conn, "/users/language/el")
      assert redirected_to(conn) == "/el/home"
    end
  end
end
