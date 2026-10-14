defmodule MehungryWeb.LegalNoticeController do
  use MehungryWeb, :controller

  def index(conn, _params) do
    render(conn, :index)
  end
end
