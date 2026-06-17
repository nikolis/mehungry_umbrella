defmodule MehungryWeb.AuthController do
  use MehungryWeb, :controller
  plug Ueberauth

  alias Mehungry.Accounts
  alias MehungryWeb.UserAuth
  alias Ueberauth.Strategy.Helpers

  def request(conn, _params) do
    render(conn, "request.html", callback_url: Helpers.callback_url(conn))
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "You have been logged out!")
    |> clear_session()
    |> redirect(to: "/")
  end

  def callback(%{assigns: %{ueberauth_failure: _fails}} = conn, _params) do
    conn
    |> put_flash(:error, "Failed to authenticate.")
    |> redirect(to: "/")
  end

  def callback(%{assigns: %{ueberauth_auth: %{provider: :pinterest} = auth}} = conn, _params) do
    token = auth.extra.raw_info.token

    token_data = %{
      "access_token" => token.access_token,
      "refresh_token" => token.refresh_token,
      "expires_at" => token.expires_at,
      "scope" => token.other_params["scope"] || ""
    }

    {target_user, redirect_path} = resolve_token_target(conn)
    Accounts.update_user_tokens(target_user, %{"pinterest_token" => token_data})

    conn
    |> delete_session("oauth_target_user_id")
    |> put_flash(:info, "Pinterest account connected successfully.")
    |> redirect(to: redirect_path)
  end

  def callback(%{assigns: %{ueberauth_auth: %{provider: :instagram} = auth}} = conn, _params) do
    short_lived_token = auth.extra.raw_info.token.access_token
    instagram_user_id = auth.extra.raw_info.token.other_params["user_id"]

    {target_user, redirect_path} = resolve_token_target(conn)

    Mehungry.Api.Instagram.get_long_lived_token(
      target_user,
      short_lived_token,
      instagram_user_id
    )

    conn
    |> delete_session("oauth_target_user_id")
    |> put_flash(:info, "Successfully connected with Instagram")
    |> redirect(to: redirect_path)
  end

  def callback(%{assigns: %{ueberauth_auth: %{provider: :facebook} = auth}} = conn, _params) do
    if conn.assigns[:current_user] do
      {target_user, redirect_path} = resolve_token_target(conn)
      token = auth.extra.raw_info.token.access_token

      Task.start(fn ->
        Mehungry.Api.Facebook.get_user_pages(target_user, token, auth.extra.raw_info.user["id"])
      end)

      conn
      |> delete_session("oauth_target_user_id")
      |> put_flash(:info, "Facebook account connected successfully.")
      |> redirect(to: redirect_path)
    else
      case Accounts.find_or_create(auth) do
        {:ok, user} ->
          token = auth.extra.raw_info.token.access_token

          Task.start(fn ->
            Accounts.put_user_token(user, token, "facebook")
            Mehungry.Api.Facebook.get_user_pages(user, token, auth.extra.raw_info.user["id"])
          end)

          conn
          |> UserAuth.log_in_user(user, %{})
          |> put_flash(:info, "Successfully logged in with Facebook.")
          |> redirect(to: "/profile")

        {:error, reason} ->
          conn
          |> put_flash(:error, reason)
          |> redirect(to: "/")
      end
    end
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    case Accounts.find_or_create(auth) do
      {:ok, user} ->
        conn
        |> UserAuth.log_in_user(user, %{})
        |> put_flash(:info, "Successfully authenticated.")

      {:error, reason} ->
        conn
        |> put_flash(:error, reason)
        |> redirect(to: "/")
    end
  end

  # When oauth_target_user_id is in session, save the token to that user (bot user)
  # and redirect back to the admin social accounts page.
  defp resolve_token_target(conn) do
    case get_session(conn, "oauth_target_user_id") do
      nil ->
        {conn.assigns.current_user, "/profile"}

      bot_user_id ->
        bot_user = Accounts.get_user!(bot_user_id)
        {bot_user, "/professional/ai-bot/social"}
    end
  end
end
