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

  def callback(%{assigns: %{ueberauth_auth: %{provider: :instagram} = auth}} = conn, _params) do
    token = auth.extra.raw_info.token.access_token
    {:ok, decoded_token} = Jason.decode(token)
    _token_save = Accounts.put_user_token(conn.assigns.current_user, token, "instagram")

    Mehungry.Api.Instagram.get_long_lived_token(
      conn.assigns.current_user,
      decoded_token["access_token"],
      decoded_token["user_id"]
    )

    conn
    |> put_flash(:info, "Successfully connected with Instagram")
    |> redirect(to: "/profile")
  end

  def callback(%{assigns: %{ueberauth_auth: %{provider: :facebook} = auth}} = conn, _params) do

    case Accounts.find_or_create(auth) do
      {:ok, user} ->
        UserAuth.log_in_user(conn, user, %{})
        IO.inspect(auth, label: "Facebook auth")
        token = auth.extra.raw_info.token.access_token
         _token_save = Accounts.put_user_token(conn.assigns.current_user, token, "facebook")
      {:error, reason} ->
        conn
        |> put_flash(:error, reason)
        |> redirect(to: "/")
    end

    conn
    |> put_flash(:info, "Successfully connected with Facebook")
    |> redirect(to: "/profile")
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do

    case Accounts.find_or_create(auth) do
      {:ok, user} ->
        UserAuth.log_in_user(conn, user, %{})

        conn
        |> put_flash(:info, "Successfully authenticated.")
        |> put_session(:current_user, user)
        |> configure_session(renew: true)
        |> redirect(to: "/")

      {:error, reason} ->
        conn
        |> put_flash(:error, reason)
        |> redirect(to: "/")
    end
  end
end
