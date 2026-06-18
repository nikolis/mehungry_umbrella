defmodule MehungryWeb.Plugs.CookieConsent do
  import Plug.Conn

  @cookie "cookie_consent"

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = fetch_cookies(conn)

    status =
      case conn.cookies[@cookie] do
        "accepted" -> :accepted
        "declined" -> :declined
        _ -> :pending
      end

    conn
    |> assign(:cookie_consent, status)
    |> put_session("cookie_consent", to_string(status))
  end
end
