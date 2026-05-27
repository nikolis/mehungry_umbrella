defmodule MehungryWeb.Plugs.CacheRawBody do
  @moduledoc """
  Stashes the raw request body in conn.assigns.raw_body before Plug.Parsers
  consumes it. Required for Stripe webhook signature verification.

  Register this as a body_reader in Plug.Parsers (see endpoint.ex):

      plug Plug.Parsers,
        parsers: [:urlencoded, :multipart, :json],
        pass: ["*/*"],
        body_reader: {MehungryWeb.Plugs.CacheRawBody, :read_body, []},
        json_decoder: Phoenix.json_library()
  """

  def read_body(conn, opts) do
    {:ok, body, conn} = Plug.Conn.read_body(conn, opts)
    conn = update_in(conn.assigns[:raw_body], fn existing -> (existing || "") <> body end)
    {:ok, body, conn}
  end
end
