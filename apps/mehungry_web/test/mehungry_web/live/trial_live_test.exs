defmodule MehungryWeb.TrialLiveTest do
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Mehungry.BetaSignups

  describe "public trial signup page" do
    test "renders the pitch and owner mailto", %{conn: conn} do
      {:ok, _lv, html} = live(conn, "/trial")
      assert html =~ "Help us test the Mehungry app"
      assert html =~ "mailto:nikolisgal@gmail.com"
      assert html =~ "Join the beta"
    end

    test "registering stores the email and shows a thank-you", %{conn: conn} do
      {:ok, lv, _html} = live(conn, "/trial")

      html =
        lv
        |> form("form[phx-submit='submit']", beta_signup: %{email: "newtester@example.com"})
        |> render_submit()

      assert html =~ "on the list!"
      assert BetaSignups.count() == 1
    end

    test "registering stores the selected platforms", %{conn: conn} do
      {:ok, lv, _html} = live(conn, "/trial")

      lv
      |> form("form[phx-submit='submit']",
        beta_signup: %{email: "picky@example.com", platforms: ["ios", "web"]}
      )
      |> render_submit()

      signup = Enum.find(BetaSignups.list_beta_signups(), &(&1.email == "picky@example.com"))
      assert signup.platforms == ["ios", "web"]
    end

    test "registering the same email twice stays friendly (idempotent)", %{conn: conn} do
      {:ok, _} = BetaSignups.create_beta_signup(%{"email" => "dupe@example.com"})

      {:ok, lv, _html} = live(conn, "/trial")

      html =
        lv
        |> form("form[phx-submit='submit']", beta_signup: %{email: "dupe@example.com"})
        |> render_submit()

      assert html =~ "on the list!"
      assert BetaSignups.count() == 1
    end

    test "the remove-me box removes a registered email", %{conn: conn} do
      {:ok, _} = BetaSignups.create_beta_signup(%{"email" => "leaving@example.com"})

      {:ok, lv, _html} = live(conn, "/trial")

      html =
        lv
        |> form("form[phx-submit='remove']", remove: %{email: "leaving@example.com"})
        |> render_submit()

      assert html =~ "been removed from the list."
      assert BetaSignups.count() == 0
    end
  end

  describe "unsubscribe link (controller)" do
    test "removes the signup for a valid token and redirects with a flash", %{conn: conn} do
      {:ok, s} = BetaSignups.create_beta_signup(%{"email" => "bye@example.com"})

      conn = get(conn, "/trial/unsubscribe/#{s.unsubscribe_token}")

      assert redirected_to(conn) == "/trial"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "bye@example.com"
      assert BetaSignups.count() == 0
    end

    test "shows an error flash for an invalid token", %{conn: conn} do
      conn = get(conn, "/trial/unsubscribe/bogus-token")

      assert redirected_to(conn) == "/trial"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "invalid"
    end
  end
end
