defmodule MehungryWeb.LegalNoticeController do
  use MehungryWeb, :controller

  def index(conn, _params) do
    conn
    |> put_view(MehungryWeb.LegalNoticeHTML)
    |> render(:index)
  end
end
