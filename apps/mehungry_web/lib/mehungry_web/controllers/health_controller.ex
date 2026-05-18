defmodule MehungryWeb.HealthController do
  use MehungryWeb, :controller
  # Add this line

  def check(conn, _params) do
    send_resp(conn, 200, "ok")
  end
end
