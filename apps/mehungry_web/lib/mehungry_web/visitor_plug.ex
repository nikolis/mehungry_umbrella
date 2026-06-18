defmodule MehungryWeb.VisitorPlug do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    if conn.assigns[:cookie_consent] == :accepted do
      case get_session(conn, :visitor_id) do
        nil -> put_session(conn, :visitor_id, Ecto.UUID.generate())
        _ -> conn
      end
    else
      conn
    end
  end
end
