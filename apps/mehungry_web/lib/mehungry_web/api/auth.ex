defmodule MehungryWeb.Api.Auth do
  @moduledoc """
  Transport-level bearer-token helpers for the mobile `/api/v1` surface, shared
  by `MehungryWeb.Api.AuthPlug` (REST) and `MehungryWeb.UserSocket` (channels).

  Mobile clients cannot use the browser session cookie, so we reuse the existing
  `"session"` token context (`Mehungry.Accounts.generate_user_session_token/1`)
  and ship it as a bearer token. Session tokens are raw 32-byte binaries, so we
  URL-base64 encode them for safe transport in an `Authorization` header and
  decode on the way back in.
  """

  alias Mehungry.Accounts

  @doc """
  Mints a new bearer token for `user` (base64-encoded session token).
  """
  def mint(user) do
    user
    |> Accounts.generate_user_session_token()
    |> Base.url_encode64(padding: false)
  end

  @doc """
  Verifies a bearer token, returning `{:ok, user}` or `:error`.
  """
  def verify(bearer) when is_binary(bearer) do
    with {:ok, raw} <- Base.url_decode64(bearer, padding: false),
         %Accounts.User{} = user <- Accounts.get_user_by_session_token(raw) do
      {:ok, user}
    else
      _ -> :error
    end
  end

  def verify(_), do: :error

  @doc """
  Revokes a bearer token (deletes the backing session token). Always `:ok`.
  """
  def revoke(bearer) when is_binary(bearer) do
    case Base.url_decode64(bearer, padding: false) do
      {:ok, raw} -> Accounts.delete_session_token(raw)
      :error -> :ok
    end
  end

  def revoke(_), do: :ok
end
