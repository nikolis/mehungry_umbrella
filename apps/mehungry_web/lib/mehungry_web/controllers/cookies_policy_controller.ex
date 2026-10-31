defmodule MehungryWeb.CookiesPolicyController do
  use MehungryWeb, :controller

  def index(conn, _params) do
    conn
    |> put_view(MehungryWeb.CookiesPolicyHTML)
    |> render(:index)
  end
end
