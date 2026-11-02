defmodule MehungryWeb.GoogleCalendarOAuthController do
  @moduledoc """
  Starts/ends a nutritionist's Google Calendar connection — a **separate** OAuth
  flow from Google login. `connect/2` marks the session with the professional's
  id and redirects into the standard Ueberauth Google request phase, but with the
  calendar scopes + `access_type=offline`/`prompt=consent` so Google returns a
  refresh token. The callback (in `AuthController`) reads the marker and persists
  the tokens. `disconnect/2` drops the stored tokens + cached busy intervals.
  """
  use MehungryWeb, :controller

  alias Mehungry.Professionals

  @calendar_scopes "openid email profile https://www.googleapis.com/auth/calendar.events https://www.googleapis.com/auth/calendar.readonly"

  def connect(conn, _params) do
    user = conn.assigns.current_user

    conn
    |> put_session("google_calendar_connect", user.id)
    |> redirect(
      to:
        "/auth/google?" <>
          URI.encode_query(%{
            "scope" => @calendar_scopes,
            "access_type" => "offline",
            "prompt" => "consent"
          })
    )
  end

  def disconnect(conn, _params) do
    user = conn.assigns.current_user
    Professionals.disconnect_google_calendar(user.id)

    conn
    |> put_flash(:info, "Google Calendar disconnected.")
    |> redirect(to: "/nutritionist/appointments")
  end
end
