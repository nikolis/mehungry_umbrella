defmodule MehungryWeb.Api.V1.SessionController do
  @moduledoc """
  Token auth for the mobile client (spec §3): register, login, OAuth exchange,
  and logout. Bearer tokens are minted via `MehungryWeb.Api.Auth` (reusing the
  existing `"session"` token context).
  """
  use MehungryWeb, :controller

  alias Mehungry.Accounts
  alias Mehungry.RateLimit
  alias MehungryWeb.Api.Auth
  alias MehungryWeb.Api.OAuthVerifier
  alias MehungryWeb.Api.V1.UserJSON

  action_fallback MehungryWeb.Api.V1.FallbackController

  @register_limit 5
  @register_window_ms 600_000

  def register(conn, params) do
    with :ok <- throttle(conn, "api_register"),
         {:ok, user} <- Accounts.register_user(registration_attrs(params)) do
      maybe_set_alias(user, params["alias"])
      token = Auth.mint(user)

      conn
      |> put_status(:created)
      |> json(UserJSON.auth(token, user, %{requires_confirmation: is_nil(user.confirmed_at)}))
    end
  end

  # `alias` lives on the profile (auto-created by register_user), not the User.
  defp maybe_set_alias(_user, blank) when blank in [nil, ""], do: :ok

  defp maybe_set_alias(user, alias_name) do
    case Accounts.get_user_profile_by_user_id(user.id) do
      nil -> :ok
      profile -> Accounts.update_user_profile(profile, %{"alias" => alias_name})
    end
  end

  def login(conn, %{"email" => email, "password" => password}) do
    case Accounts.get_user_by_email_and_password(email, password) do
      nil ->
        {:error, :unauthorized}

      user ->
        token = Auth.mint(user)
        json(conn, UserJSON.auth(token, user))
    end
  end

  def login(conn, _params), do: send_error(conn, :bad_request)

  def oauth(conn, %{"provider" => provider} = params) do
    with {:ok, profile} <- OAuthVerifier.verify_provider(provider, params),
         {:ok, user} <- Accounts.find_or_create_from_profile(profile) do
      token = Auth.mint(user)
      json(conn, UserJSON.auth(token, user))
    else
      {:error, %Ecto.Changeset{} = cs} -> conn |> MehungryWeb.Api.V1.FallbackController.call({:error, cs})
      {:error, _reason} -> send_error(conn, :unauthorized)
    end
  end

  def delete(conn, _params) do
    conn |> MehungryWeb.Api.AuthPlug.bearer_token() |> Auth.revoke()
    send_resp(conn, :no_content, "")
  end

  defp registration_attrs(params) do
    %{
      "email" => params["email"],
      "password" => params["password"],
      "alias" => params["alias"]
    }
  end

  defp throttle(conn, prefix) do
    key = prefix <> ":" <> client_ip(conn)

    case RateLimit.hit(key, @register_limit, @register_window_ms) do
      :ok -> :ok
      {:error, :rate_limited} -> {:error, :rate_limited}
    end
  end

  defp client_ip(conn) do
    case Plug.Conn.get_req_header(conn, "x-forwarded-for") do
      [value | _] -> value |> String.split(",") |> List.first() |> String.trim()
      [] -> conn.remote_ip |> :inet.ntoa() |> to_string()
    end
  end

  defp send_error(conn, :bad_request),
    do: conn |> put_status(:bad_request) |> json(%{errors: %{detail: "Bad request"}})

  defp send_error(conn, :unauthorized),
    do: conn |> put_status(:unauthorized) |> json(%{errors: %{detail: "unauthorized"}})
end
