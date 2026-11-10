defmodule MehungryWeb.SocialOAuthControllerTest do
  @moduledoc """
  The social-connect entry point must carry an *explicit* intent so a connect
  can never be confused with (or leak into) a login. These lock the separation:

    * self-connect targets the logged-in user — not a stale/forged bot id;
    * Facebook connect requests the `pages_*` publishing scopes per-request,
      while plain login (bare `/auth/facebook`) does not;
    * connecting a managed bot user's account is admin-only.
  """
  use MehungryWeb.ConnCase, async: true

  import Mehungry.AccountsFixtures

  @admin_email Application.compile_env(:mehungry, :admin_email)

  describe "GET /auth/connect/:provider (self-connect)" do
    setup :register_and_log_in_user

    test "sets a connect intent targeting the logged-in user", %{conn: conn, user: user} do
      conn = get(conn, "/auth/connect/pinterest")

      assert redirected_to(conn) == "/auth/pinterest"

      assert get_session(conn, "oauth_intent") == %{
               "action" => "connect",
               "target" => to_string(user.id)
             }
    end

    test "Facebook connect requests the Page publishing scopes per-request", %{conn: conn} do
      conn = get(conn, "/auth/connect/facebook")

      redirect = redirected_to(conn)
      assert redirect =~ "/auth/facebook?scope="
      assert redirect =~ "pages_manage_posts"
    end

    test "requires authentication" do
      conn = build_conn() |> get("/auth/connect/facebook")
      assert redirected_to(conn) =~ "/login"
      refute get_session(conn, "oauth_intent")
    end
  end

  describe "GET /auth/bot/target/:bot_user_id/:provider (bot-connect)" do
    test "a non-admin cannot connect a bot user's account", %{conn: conn} do
      user = user_fixture()
      bot = user_fixture()
      conn = log_in_user(conn, user)

      conn = get(conn, "/auth/bot/target/#{bot.id}/facebook")

      assert conn.status == 404
      refute get_session(conn, "oauth_intent")
    end

    test "an admin connects the bot user's account via an explicit target intent", %{conn: conn} do
      admin = user_fixture(%{email: @admin_email})
      bot = user_fixture()
      conn = log_in_user(conn, admin)

      conn = get(conn, "/auth/bot/target/#{bot.id}/instagram")

      assert redirected_to(conn) == "/auth/instagram"

      assert get_session(conn, "oauth_intent") == %{
               "action" => "connect",
               "target" => to_string(bot.id)
             }
    end
  end
end
