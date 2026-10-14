defmodule MehungryWeb.AndroidBetaLiveTest do
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mehungry.AccountsFixtures

  @admin_email Application.compile_env(:mehungry, :admin_email)

  describe "access control" do
    test "non-admin is redirected", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)
      assert {:error, {:redirect, %{to: "/home"}}} = live(conn, "/professional/android-beta")
    end
  end

  describe "as admin" do
    setup %{conn: conn} do
      admin = user_fixture(%{email: @admin_email})
      %{conn: log_in_user(conn, admin)}
    end

    test "renders the form prefilled with the group address", %{conn: conn} do
      {:ok, _lv, html} = live(conn, "/professional/android-beta")
      assert html =~ "Android Beta Invite"
      assert html =~ Mehungry.Accounts.android_beta_group_email()
    end

    test "renders the shareable recruitment post with the trial link", %{conn: conn} do
      {:ok, _lv, html} = live(conn, "/professional/android-beta")
      assert html =~ "Recruitment post"
      assert html =~ "a nutrition app with a focus on"
      assert html =~ "https://www.m3hungry.com/trial"
    end

    test "sends invites to valid recipients and skips invalid ones", %{conn: conn} do
      {:ok, lv, _html} = live(conn, "/professional/android-beta")

      lv
      |> form("form",
        invite: %{
          recipients: "good@example.com, not-an-email",
          opt_in_url: "https://play.google.com/apps/testing/x",
          intro: ""
        }
      )
      |> render_submit()

      html = render(lv)
      assert html =~ "Sent 1 invite"
      assert html =~ "good@example.com"
      assert html =~ "not-an-email"
    end

    test "refuses to send without a valid recipient", %{conn: conn} do
      {:ok, lv, _html} = live(conn, "/professional/android-beta")

      html =
        lv
        |> form("form",
          invite: %{recipients: "", opt_in_url: "https://x", intro: ""}
        )
        |> render_submit()

      assert html =~ "at least one valid recipient"
    end

    test "lists registered testers and loads them into recipients", %{conn: conn} do
      {:ok, _} = Mehungry.BetaSignups.create_beta_signup(%{"email" => "signup@example.com"})

      {:ok, lv, html} = live(conn, "/professional/android-beta")
      assert html =~ "Registered testers"
      assert html =~ "signup@example.com"

      html = lv |> element("button", "Load Android testers") |> render_click()
      assert html =~ "signup@example.com"
    end

    test "Load Android testers excludes non-Android signups", %{conn: conn} do
      {:ok, _} =
        Mehungry.BetaSignups.create_beta_signup(%{
          "email" => "android@example.com",
          "platforms" => ["android"]
        })

      {:ok, _} =
        Mehungry.BetaSignups.create_beta_signup(%{
          "email" => "webonly@example.com",
          "platforms" => ["web"]
        })

      {:ok, lv, _html} = live(conn, "/professional/android-beta")
      html = lv |> element("button", "Load Android testers") |> render_click()

      assert html =~ "android@example.com</textarea>"
      refute html =~ "webonly@example.com</textarea>"
    end

    test "deletes a registered tester", %{conn: conn} do
      {:ok, s} = Mehungry.BetaSignups.create_beta_signup(%{"email" => "deleteme@example.com"})

      {:ok, lv, _html} = live(conn, "/professional/android-beta")

      lv
      |> element("button[phx-value-id='#{s.id}']")
      |> render_click()

      assert Mehungry.BetaSignups.count() == 0
    end

    test "sending records the version per tester and shows the badge", %{conn: conn} do
      {:ok, _} = Mehungry.BetaSignups.create_beta_signup(%{"email" => "got@example.com"})

      {:ok, lv, _html} = live(conn, "/professional/android-beta")

      html =
        lv
        |> form("form",
          invite: %{
            recipients: "got@example.com",
            opt_in_url: "https://play.google.com/apps/testing/x",
            intro: "",
            version: "2.0.0"
          }
        )
        |> render_submit()

      assert html =~ "Sent 1 invite for 2.0.0"
      assert Mehungry.BetaSignups.versions_by_tester()["got@example.com"] == ["2.0.0"]
      # the tester row now carries the ✓ 2.0.0 badge
      assert html =~ "✓ 2.0.0"
    end

    test "load missing loads only testers without the current version", %{conn: conn} do
      {:ok, _} = Mehungry.BetaSignups.create_beta_signup(%{"email" => "got@example.com"})
      {:ok, _} = Mehungry.BetaSignups.create_beta_signup(%{"email" => "missing@example.com"})
      {:ok, _} = Mehungry.BetaSignups.record_send("got@example.com", "2.0.0")

      {:ok, lv, _html} = live(conn, "/professional/android-beta")

      # set the version field to 2.0.0, then load missing
      lv
      |> form("form", invite: %{version: "2.0.0", opt_in_url: "https://x", recipients: "", intro: ""})
      |> render_change()

      html = lv |> element("button", "Load testers missing") |> render_click()

      # only the tester without 2.0.0 ends up in the recipients textarea
      assert html =~ "missing@example.com</textarea>"
      refute html =~ "got@example.com</textarea>"
    end
  end
end
