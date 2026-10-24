defmodule MehungryWeb.Api.AuthPlug do
  @moduledoc """
  Requires a valid mobile bearer token. On success assigns `:current_user`;
  otherwise halts with `401` in the standard API error envelope.
  """
  import Plug.Conn

  alias MehungryWeb.Api.Auth

  def init(opts), do: opts

  def call(conn, _opts) do
    case Auth.verify(bearer_token(conn)) do
      {:ok, user} -> assign(conn, :current_user, user)
      :error -> unauthorized(conn)
    end
  end

  defp unauthorized(conn) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(401, Jason.encode!(%{errors: %{detail: "unauthorized"}}))
    |> halt()
  end

  @doc false
  def bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token | _] -> token
      _ -> nil
    end
  end
end

defmodule MehungryWeb.Api.MaybeApiAuthPlug do
  @moduledoc """
  Optional auth for 🔓 endpoints: assigns `:current_user` when a valid bearer
  token is present, otherwise assigns `nil` and continues (never 401s). Lets
  public endpoints personalize for logged-in callers.
  """
  import Plug.Conn

  alias MehungryWeb.Api.Auth
  alias MehungryWeb.Api.AuthPlug

  def init(opts), do: opts

  def call(conn, _opts) do
    case Auth.verify(AuthPlug.bearer_token(conn)) do
      {:ok, user} -> assign(conn, :current_user, user)
      :error -> assign(conn, :current_user, nil)
    end
  end
end
