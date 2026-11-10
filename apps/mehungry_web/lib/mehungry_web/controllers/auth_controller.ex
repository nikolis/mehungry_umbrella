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
        |> delete_session("oauth_intent")
        |> put_flash(:info, "Pinterest account connected successfully.")
        |> redirect(to: redirect_path)

      error ->
        handle_connect_error(conn, error)
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
        |> delete_session("oauth_intent")
        |> redirect(to: redirect_path)

      error ->
        handle_connect_error(conn, error)
    end
  end

  # Facebook is the one provider used for BOTH login and connect, so it branches
  # on the explicit connect intent (not on "is someone logged in?"): a connect
  # intent attaches the Page token to the resolved target; anything else is a
  # normal Facebook login / account claim.
  def callback(%{assigns: %{ueberauth_auth: %{provider: :facebook} = auth}} = conn, _params) do
    case resolve_token_target(conn) do
      {:ok, target_user, redirect_path} ->
        token = auth.extra.raw_info.token.access_token

        Task.Supervisor.start_child(MehungryWeb.TaskSupervisor, fn ->
          Mehungry.Social.Facebook.get_user_pages(
            target_user,
            token,
            auth.extra.raw_info.user["id"]
          )
        end)

        conn
        |> delete_session("oauth_intent")
        |> put_flash(:info, "Facebook account connected successfully.")
        |> redirect(to: redirect_path)

      :no_connect_intent ->
        facebook_login_or_claim(conn, auth)

      error ->
        handle_connect_error(conn, error)
    end
  end

  # Google: a nutritionist connecting their calendar carries a
  # `google_calendar_connect` session marker (set by GoogleCalendarOAuthController)
  # and the extra calendar scopes + offline refresh token. Without the marker it
  # is an ordinary Google sign-in.
  def callback(%{assigns: %{ueberauth_auth: %{provider: :google} = auth}} = conn, _params) do
    case get_session(conn, "google_calendar_connect") do
      nil -> login_or_claim(conn, auth)
      professional_id -> connect_google_calendar(conn, auth, professional_id)
    end
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    login_or_claim(conn, auth)
  end

  defp facebook_login_or_claim(conn, auth) do
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

  defp login_or_claim(conn, auth) do
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

  # Persist the per-nutritionist calendar OAuth tokens, then return to the
  # appointments screen. Guards that the connecting session actually belongs to
  # the marked professional so a stale/forged marker can't bind someone else's
  # tokens.
  defp connect_google_calendar(conn, auth, professional_id) do
    conn = delete_session(conn, "google_calendar_connect")
    current = conn.assigns[:current_user]

    cond do
      is_nil(current) ->
        conn
        |> put_flash(:error, "Please log in before connecting Google Calendar.")
        |> redirect(to: "/users/log_in")

      current.id != professional_id ->
        conn
        |> put_flash(:error, "Could not connect Google Calendar.")
        |> redirect(to: "/nutritionist/appointments")

      true ->
        case Mehungry.Professionals.connect_google_calendar(
               professional_id,
               google_token_response(auth)
             ) do
          {:ok, _account} ->
            Mehungry.ObanWorkers.GoogleCalendarBusyImportWorker.enqueue(professional_id)

            conn
            |> put_flash(:info, "Google Calendar connected — your appointments will sync.")
            |> redirect(to: "/nutritionist/appointments")

          {:error, _changeset} ->
            conn
            |> put_flash(:error, "Could not connect Google Calendar. Please try again.")
            |> redirect(to: "/nutritionist/appointments")
        end
    end
  end

  # Normalize the Ueberauth Google credentials into the token-response shape
  # `Professionals.connect_google_calendar/2` expects.
  defp google_token_response(%{credentials: creds}) do
    expires_in =
      case creds.expires_at do
        at when is_integer(at) -> at - System.system_time(:second)
        _ -> nil
      end

    %{
      "access_token" => creds.token,
      "refresh_token" => creds.refresh_token,
      "expires_in" => expires_in,
      "scope" => creds.scopes |> List.wrap() |> Enum.join(" ")
    }
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

  # Resolve which user a connect callback should attach the token to, from the
  # explicit `oauth_intent` set by SocialOAuthController. There is no implicit
  # "logged-in ⇒ connect" path: a callback with no connect intent is a login
  # (`:no_connect_intent`), a connect with a dropped session needs login
  # (`:needs_login`), and a connect whose target isn't yours — unless you're an
  # admin connecting a managed bot user — is refused (`:forbidden`). You may
  # always connect your own account; only an admin may connect a bot user's.
  defp resolve_token_target(conn) do
    case get_session(conn, "oauth_intent") do
      %{"action" => "connect", "target" => target} ->
        current = conn.assigns[:current_user]

        cond do
          is_nil(current) -> :needs_login
          to_string(current.id) == target -> {:ok, current, "/profile"}
          admin?(current) -> {:ok, Accounts.get_user!(target), "/professional/ai-bot/social"}
          true -> :forbidden
        end

      _ ->
        :no_connect_intent
    end
  end

  defp admin?(%{email: email}) do
    admin_email = Application.get_env(:mehungry, :admin_email)
    is_binary(admin_email) and email == admin_email
  end

  defp admin?(_), do: false

  # A connect callback that couldn't resolve a valid target. `:no_connect_intent`
  # on a connect-only provider (Instagram/Pinterest) means the request arrived
  # without going through SocialOAuthController, so treat it as a login prompt.
  defp handle_connect_error(conn, :forbidden) do
    conn
    |> delete_session("oauth_intent")
    |> put_flash(:error, "You are not allowed to connect that account.")
    |> redirect(to: "/profile")
  end

  defp handle_connect_error(conn, _needs_login_or_no_intent), do: redirect_needs_login(conn)

  defp redirect_needs_login(conn) do
    conn
    |> delete_session("oauth_intent")
    |> put_flash(:error, "Please log in before connecting an account.")
    |> redirect(to: "/users/log_in")
  end
end
