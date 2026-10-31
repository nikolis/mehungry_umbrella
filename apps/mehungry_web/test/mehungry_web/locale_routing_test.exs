defmodule MehungryWeb.LocaleRoutingTest do
  use MehungryWeb.ConnCase, async: true

  describe "locale-prefixed routing" do
    test "bare / sends an unrecognized visitor to the bare welcome page (so the chooser shows)",
         %{conn: conn} do
      conn = get(conn, "/")
      # No explicit language choice yet → land on the bare (unprefixed) welcome
      # so the first-visit language chooser can trigger.
      assert redirected_to(conn) == "/welcome"
    end

    test "bare / sends a visitor who already chose a language to their localized welcome",
         %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{"locale_selected" => true, "locale" => "el"})
        |> get("/")

      assert redirected_to(conn) == "/el/welcome"
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

    test "an unrecognized visitor sees the language chooser on a bare public page", %{conn: conn} do
      html = conn |> get("/welcome") |> html_response(200)
      assert html =~ ~s(id="language-chooser")
    end

    test "a locale-prefixed page does not show the language chooser", %{conn: conn} do
      html = conn |> get("/el/welcome") |> html_response(200)
      refute html =~ ~s(id="language-chooser")
    end

    test "a visitor who already chose a language sees no chooser on a bare page", %{conn: conn} do
      html =
        conn
        |> init_test_session(%{"locale_selected" => true})
        |> get("/welcome")
        |> html_response(200)

      refute html =~ ~s(id="language-chooser")
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
