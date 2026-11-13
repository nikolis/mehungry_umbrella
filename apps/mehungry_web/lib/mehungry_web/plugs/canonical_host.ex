defmodule MehungryWeb.Plugs.CanonicalHost do
  @moduledoc """
  301-redirects the bare apex `m3hungry.com` to the canonical `www.m3hungry.com`,
  preserving the path and query string.

  The apex now has a valid TLS cert and serves the full app, so without this plug
  every page is reachable under two hosts — duplicate content that splits link
  equity and relies solely on the per-page `rel=canonical` hint to consolidate.
  A host-level 301 is the directive (not a hint) Google wants.

  Scoped to the exact apex host only, so localhost, `www.*`, `*.fly.dev`, and
  Fly's internal health-check host are never touched.
  """

  import Plug.Conn

  @apex "m3hungry.com"
  @canonical_host "www.m3hungry.com"

  def init(opts), do: opts

  def call(%Plug.Conn{host: @apex} = conn, _opts) do
    query = if conn.query_string in [nil, ""], do: "", else: "?" <> conn.query_string
    location = "https://" <> @canonical_host <> conn.request_path <> query

    conn
    |> put_resp_header("location", location)
    |> put_resp_header("cache-control", "public, max-age=3600")
    |> send_resp(:moved_permanently, "")
    |> halt()
  end

  def call(conn, _opts), do: conn
end
