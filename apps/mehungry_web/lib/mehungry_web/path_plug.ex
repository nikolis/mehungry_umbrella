defmodule MehungryWeb.PathPlug do
  @moduledoc false

  import Plug.Conn

  def init(opts), do: opts

  def fetch_path_info(conn, _opts) do
    conn = put_session(conn, :path, conn.request_path)
    assign(conn, :path, conn.request_path)
  end
end
