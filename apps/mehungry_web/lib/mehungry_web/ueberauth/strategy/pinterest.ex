defmodule Ueberauth.Strategy.Pinterest do
  @moduledoc """
  Pinterest OAuth2 strategy for Ueberauth.
  Handles the connect-account flow (not login); tokens are stored and
  used later for creating pins via the Pinterest v5 API.
  """

  use Ueberauth.Strategy,
    default_scope: "boards:read,pins:read,pins:write,user_accounts:read",
    uid_field: :username,
    allowed_request_params: [:scope]

  alias Ueberauth.Auth.{Info, Credentials, Extra}

  @user_url "https://api.pinterest.com/v5/user_account"

  def handle_request!(conn) do
    allowed_params =
      conn
      |> option(:allowed_request_params)
      |> Enum.map(&to_string/1)

    params =
      conn.params
      |> maybe_replace_param(conn, "scope", :default_scope)
      |> Enum.filter(fn {k, _v} -> Enum.member?(allowed_params, k) end)
      |> Enum.map(fn {k, v} -> {String.to_existing_atom(k), v} end)
      |> Keyword.put(:redirect_uri, callback_url(conn))
      |> with_state_param(conn)

    authorize_url = Ueberauth.Strategy.Pinterest.OAuth.authorize_url!(params)
    redirect!(conn, authorize_url)
  end

  def handle_callback!(%Plug.Conn{params: %{"code" => code}} = conn) do
    opts = [redirect_uri: callback_url(conn)]
    client = Ueberauth.Strategy.Pinterest.OAuth.get_token!([code: code], opts)
    token = client.token

    if token.access_token == nil do
      err = token.other_params["error"]
      desc = token.other_params["error_description"]
      set_errors!(conn, [error(err, desc)])
    else
      fetch_user(conn, token)
    end
  end

  def handle_callback!(conn) do
    set_errors!(conn, [error("missing_code", "No code received")])
  end

  def handle_cleanup!(conn) do
    conn
    |> put_private(:pinterest_user, nil)
    |> put_private(:pinterest_token, nil)
  end

  def uid(conn) do
    conn.private.pinterest_user["username"] || conn.private.pinterest_user["id"] || ""
  end

  def credentials(conn) do
    token = conn.private.pinterest_token

    %Credentials{
      expires: !!token.expires_at,
      expires_at: token.expires_at,
      token: token.access_token,
      refresh_token: token.refresh_token,
      scopes: String.split(token.other_params["scope"] || "", ",")
    }
  end

  def info(conn) do
    user = conn.private.pinterest_user

    %Info{
      nickname: user["username"],
      name: user["username"],
      image: user["profile_image"],
      urls: %{website: user["website_url"]}
    }
  end

  def extra(conn) do
    %Extra{
      raw_info: %{
        token: conn.private.pinterest_token,
        user: conn.private.pinterest_user
      }
    }
  end

  defp fetch_user(conn, token) do
    conn = put_private(conn, :pinterest_token, token)

    case HTTPoison.get(@user_url, [{"Authorization", "Bearer #{token.access_token}"}]) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, user} -> put_private(conn, :pinterest_user, user)
          _ -> put_private(conn, :pinterest_user, %{})
        end

      _ ->
        put_private(conn, :pinterest_user, %{})
    end
  end

  defp option(conn, key) do
    default = Keyword.get(default_options(), key)
    conn |> options() |> Keyword.get(key, default)
  end

  defp option(nil, conn, key), do: option(conn, key)
  defp option(value, _conn, _key), do: value

  defp maybe_replace_param(params, conn, name, config_key) do
    if params[name] do
      params
    else
      Map.put(params, name, option(params[name], conn, config_key))
    end
  end
end
