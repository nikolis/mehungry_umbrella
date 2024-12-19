defmodule MehungryWeb.CalendarFeatureTest do
  use MehungryWeb.FeatureCase, async: true

  alias MehungryWeb.Endpoint
  alias MehungryWeb.Router.Helpers, as: Routes

  describe "Calendar Index" do
    test "Test Create Callendar Meal Entry", %{session: session} do
      {session, _user} = log_in(%{session: session})

      session
      |> visit(Routes.calendar_index_path(Endpoint, :index))
      |> sleep()
      |> click(button("button_calendar"))
      |> sleep()
    end
  end

  def sleep(session) do
    Process.sleep(500)
    session
  end

  @user_remember_me "_mehungry_web_user_remember_me"

  def log_in(%{session: session} = _context) do
    user = Mehungry.AccountsFixtures.user_fixture()
    user_token = Mehungry.Accounts.generate_user_session_token(user)

    endpoint_opts = Application.get_env(:mehungry_web, MehungryWeb.Endpoint)
    secret_key_base = Keyword.fetch!(endpoint_opts, :secret_key_base)

    conn =
      %Plug.Conn{secret_key_base: secret_key_base}
      |> Plug.Conn.put_resp_cookie(@user_remember_me, user_token, sign: true)

    session
    |> visit("/")
    |> set_cookie(@user_remember_me, conn.resp_cookies[@user_remember_me][:value])

    {session, user}
  end
end
