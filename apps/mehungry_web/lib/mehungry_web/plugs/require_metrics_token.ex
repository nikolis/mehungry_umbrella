defmodule MehungryWeb.Plugs.RequireMetricsToken do
  @moduledoc """
  Shared-secret bearer-token guard for the Prometheus scrape endpoint (`GET /metrics`).
  Session-based admin auth can't be used by a Prometheus scraper, so this mirrors the
  `RequireLocalAiToken` pattern (no session/`current_user`).

  Expects `Authorization: Bearer <token>` matching `:mehungry, :metrics_api_token`
  (constant-time compare). Returns 401 on mismatch/missing, 500 when the secret is
  not configured on the server. Configure a Prometheus scrape job with:

      authorization:
        credentials: <token>
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    configured = Application.get_env(:mehungry, :metrics_api_token)

    cond do
      is_nil(configured) or configured == "" ->
        deny(conn, 500, "metrics_api_token not configured")

      valid?(conn, configured) ->
        conn

      true ->
        deny(conn, 401, "unauthorized")
    end
  end

  defp valid?(conn, configured) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token | _] -> Plug.Crypto.secure_compare(token, configured)
      _ -> false
    end
  end

  defp deny(conn, status, message) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(status, message)
    |> halt()
  end
end
