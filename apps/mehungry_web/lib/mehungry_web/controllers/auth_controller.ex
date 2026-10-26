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
    case resolve_token_target(conn) do
      {:ok, target_user, redirect_path} ->
        token = auth.extra.raw_info.token

        token_data =
          Mehungry.Social.Pinterest.Token.build(%{
            "access_token" => token.access_token,
            "refresh_token" => token.refresh_token,
            "expires_at" => token.expires_at,
            "scope" => token.other_params["scope"] || ""
          })

        Accounts.update_user_tokens(target_user, %{"pinterest_token" => token_data})

        conn
        |> delete_session("oauth_target_user_id")
        |> put_flash(:info, "Pinterest account connected successfully.")
        |> redirect(to: redirect_path)

      :needs_login ->
        redirect_needs_login(conn)
    end
  end

  def callback(%{assigns: %{ueberauth_auth: %{provider: :instagram} = auth}} = conn, _params) do
    case resolve_token_target(conn) do
      {:ok, target_user, redirect_path} ->
        short_lived_token = auth.extra.raw_info.token.access_token
        instagram_user_id = auth.extra.raw_info.token.other_params["user_id"]

        conn =
          case Mehungry.Social.Instagram.connect_account(
                 target_user,
                 short_lived_token,
                 instagram_user_id
               ) do
            {:ok, _user} ->
              put_flash(conn, :info, "Successfully connected with Instagram")

            {:error, reason} ->
              put_flash(conn, :error, "Instagram connection failed: #{inspect(reason)}")
          end

        conn
        |> delete_session("oauth_target_user_id")
        |> redirect(to: redirect_path)

      :needs_login ->
        redirect_needs_login(conn)
    end
  end

  def callback(%{assigns: %{ueberauth_auth: %{provider: :facebook} = auth}} = conn, _params) do
    if conn.assigns[:current_user] do
      {:ok, target_user, redirect_path} = resolve_token_target(conn)
      token = auth.extra.raw_info.token.access_token

      Task.Supervisor.start_child(MehungryWeb.TaskSupervisor, fn ->
        Mehungry.Social.Facebook.get_user_pages(
          target_user,
          token,
          auth.extra.raw_info.user["id"]
        )
      end)

      conn
      |> delete_session("oauth_target_user_id")
      |> put_flash(:info, "Facebook account connected successfully.")
      |> redirect(to: redirect_path)
    else
      case get_session(conn, "claim_token") do
        nil ->
          case Accounts.find_or_create(auth) do
            {:ok, user, status} ->
              token = auth.extra.raw_info.token.access_token

              Task.Supervisor.start_child(MehungryWeb.TaskSupervisor, fn ->
                Accounts.put_user_token(user, token, "facebook")

                Mehungry.Social.Facebook.get_user_pages(
                  user,
                  token,
                  auth.extra.raw_info.user["id"]
                )
              end)

              conn
              # renew_session in log_in_user wipes the session, so the sign_up
              # GA flash must be set *after* it (same as the :info flash below).
              |> UserAuth.log_in_user(user, %{})
              |> maybe_track_signup(status, :facebook)
              |> put_flash(:info, "Successfully logged in with Facebook.")
              |> redirect(to: "/profile")

            {:error, reason} ->
              conn
              |> put_flash(:error, reason)
              |> redirect(to: "/")
          end

        claim_token ->
          fb_token = auth.extra.raw_info.token.access_token

          claim_via_oauth(conn, claim_token, auth, fn user ->
            Task.Supervisor.start_child(MehungryWeb.TaskSupervisor, fn ->
              Accounts.put_user_token(user, fb_token, "facebook")
            end)
          end)
      end
    end
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    case get_session(conn, "claim_token") do
      nil ->
        case Accounts.find_or_create(auth) do
          {:ok, user, status} ->
            conn
            |> UserAuth.log_in_user(user, %{})
            |> maybe_track_signup(status, auth.provider)
            |> put_flash(:info, "Successfully authenticated.")

          {:error, reason} ->
            conn
            |> put_flash(:error, reason)
            |> redirect(to: "/")
        end

      claim_token ->
        claim_via_oauth(conn, claim_token, auth)
    end
  end

  # Fire the GA4 `sign_up` key event for OAuth, but only for a genuinely new
  # account (`:created`) — a returning Facebook/Google login must not count as a
  # signup. Uses the controller flash seam (see docs/implementation/infrastructure/google_analytics.md);
  # must be piped after `log_in_user` since that renews (clears) the session.
  defp maybe_track_signup(conn, :created, provider) do
    put_flash(
      conn,
      :ga_event,
      Jason.encode!(%{name: "sign_up", params: %{method: to_string(provider)}})
    )
  end

  defp maybe_track_signup(conn, _status, _provider), do: conn

  # Claim a professional-created managed account with the provider identity,
  # then log in. `after_claim` runs any provider-specific side effects (e.g.
  # storing a Facebook token) on success.
  defp claim_via_oauth(conn, token, auth, after_claim \\ fn _user -> :ok end) do
    conn = delete_session(conn, "claim_token")

    case Accounts.claim_managed_account_with_oauth(token, Accounts.oauth_profile(auth)) do
      {:ok, user} ->
        after_claim.(user)

        conn
        |> UserAuth.log_in_user(user, %{})
        |> put_flash(:info, "Welcome! Your account is ready.")
        |> redirect(to: "/profile")

      {:error, :email_taken} ->
        conn
        |> put_flash(
          :error,
          "An account with that email already exists. Please log in with it instead."
        )
        |> redirect(to: "/users/log_in")

      :error ->
        conn
        |> put_flash(:error, "This claim link is invalid or has expired.")
        |> redirect(to: "/")
    end
  end

  # When oauth_target_user_id is in session, save the token to that user (bot user)
  # and redirect back to the admin social accounts page. Otherwise save to the
  # logged-in user. Returns `:needs_login` when neither is present, so a connect
  # attempt with a missing/dropped session is sent to log in rather than raising
  # a 500 on a nil user (which read to users as a failed connect / logout).
  defp resolve_token_target(conn) do
    case get_session(conn, "oauth_target_user_id") do
      nil ->
        case conn.assigns[:current_user] do
          nil -> :needs_login
          user -> {:ok, user, "/profile"}
        end

      bot_user_id ->
        bot_user = Accounts.get_user!(bot_user_id)
        {:ok, bot_user, "/professional/ai-bot/social"}
    end
  end

  defp redirect_needs_login(conn) do
    conn
    |> delete_session("oauth_target_user_id")
    |> put_flash(:error, "Please log in before connecting an account.")
    |> redirect(to: "/users/log_in")
  end
end
