defmodule MehungryWeb.Plugs.RequireLocalAiToken do
  @moduledoc """
  Shared-secret bearer-token guard for the local-AI REST API (`/api/local_ai/*`),
  which the non-deployed `mehungry_local_ai` service calls from a machine with GPU
  hardware. Modeled on the Stripe-webhook secret pattern (no session/`current_user`).

  Expects `Authorization: Bearer <token>` matching `:mehungry, :local_ai_api_token`
  (constant-time compare). Returns 401 on mismatch/missing, 500 when the secret is
  not configured on the server.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    configured = Application.get_env(:mehungry, :local_ai_api_token)

    cond do
      is_nil(configured) or configured == "" ->
        deny(conn, 500, "local_ai_api_token not configured")

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
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(%{error: message}))
    |> halt()
  end
end
