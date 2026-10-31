defmodule MehungryWeb.TermsController do
  use MehungryWeb, :controller

  def index(conn, _params) do
    conn
    |> put_view(MehungryWeb.TermsHTML)
    |> render(:index)
  end
end
