defmodule MehungryWeb.ConsentController do
  use MehungryWeb, :controller

  @cookie "cookie_consent"
  @cookie_opts [max_age: 31_536_000, same_site: "Lax"]

  def accept(conn, _params) do
    conn
    |> put_resp_cookie(@cookie, "accepted", @cookie_opts)
    |> redirect(to: referer_or_root(conn))
  end

  def decline(conn, _params) do
    conn
    |> put_resp_cookie(@cookie, "declined", @cookie_opts)
    |> redirect(to: referer_or_root(conn))
  end

  defp referer_or_root(conn) do
    case get_req_header(conn, "referer") do
      [referer | _] -> URI.parse(referer).path || "/"
      [] -> "/"
    end
  end
end
