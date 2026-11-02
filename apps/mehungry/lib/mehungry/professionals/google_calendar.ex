defmodule Mehungry.Professionals.GoogleCalendar do
  @moduledoc """
  Orchestration layer between the `Professionals` context and the Google
  Calendar HTTP client: ensures a fresh access token (refreshing + persisting on
  demand), builds event payloads from appointments, and exposes the high-level
  operations the sync workers call.

  The HTTP client is resolved through the `:google_calendar_client` config key
  so tests can stub it (mirrors `:instagram_client`).
  """

  require Logger

  alias Mehungry.Professionals
  alias Mehungry.Professionals.{Appointment, GoogleAccount}

  @default_client Mehungry.Professionals.GoogleCalendar.Client

  @doc "The configured Google Calendar client module (stubbable in tests)."
  def client do
    Application.get_env(:mehungry, :google_calendar_client, @default_client)
  end

  @doc """
  Ensure the account's access token is fresh, refreshing via the stored
  refresh token and persisting the new token when needed. Returns
  `{:ok, account}` with a usable `access_token`, or `{:error, reason}`.
  """
  def ensure_fresh_token(%GoogleAccount{} = account) do
    if GoogleAccount.access_token_expired?(account) do
      refresh_token(account)
    else
      {:ok, account}
    end
  end

  defp refresh_token(%GoogleAccount{refresh_token: nil}), do: {:error, :no_refresh_token}

  defp refresh_token(%GoogleAccount{refresh_token: refresh} = account) do
    case client().refresh_access_token(refresh) do
      {:ok, response} ->
        Professionals.update_google_account(account, GoogleAccount.token_attrs(response))

      {:error, reason} ->
        Logger.error("[GoogleCalendar] token refresh failed for ##{account.professional_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Push an accepted appointment to the nutritionist's Google Calendar: inserts a
  new event (minting a Meet link + inviting the client) or patches the existing
  one when `google_event_id` is already set. Persists `google_event_id` and the
  Meet URL back onto the appointment.

  Returns `{:ok, appointment}`, `:skip` (no connected calendar), or
  `{:error, reason}` — callers treat any non-`{:ok}` as a best-effort miss and
  fall back to the manual `meeting_url`.
  """
  def sync_appointment(%Appointment{} = appointment) do
    case Professionals.get_google_account(appointment.professional_id) do
      nil ->
        :skip

      account ->
        with {:ok, account} <- ensure_fresh_token(account) do
          do_sync(appointment, account)
        end
    end
  end

  defp do_sync(%Appointment{google_event_id: nil} = appointment, account) do
    event = build_event(appointment)

    with {:ok, created} <-
           client().insert_event(account.access_token, account.calendar_id, event) do
      meeting_url = appointment.meeting_url || extract_meet_url(created)
      Professionals.put_appointment_google_event(appointment, created["id"], meeting_url)
    end
  end

  defp do_sync(%Appointment{google_event_id: event_id} = appointment, account) do
    event = build_event(appointment)

    with {:ok, updated} <-
           client().update_event(account.access_token, account.calendar_id, event_id, event) do
      meeting_url = appointment.meeting_url || extract_meet_url(updated)
      Professionals.put_appointment_google_event(appointment, event_id, meeting_url)
    end
  end

  @doc """
  Delete an appointment's Google Calendar event (on decline/cancel). No-op if it
  was never pushed or there's no connected calendar.
  """
  def delete_appointment_event(%Appointment{google_event_id: nil}), do: :skip

  def delete_appointment_event(%Appointment{google_event_id: event_id} = appointment) do
    case Professionals.get_google_account(appointment.professional_id) do
      nil ->
        :skip

      account ->
        with {:ok, account} <- ensure_fresh_token(account) do
          client().delete_event(account.access_token, account.calendar_id, event_id)
        end
    end
  end

  @doc """
  Import the nutritionist's Google busy intervals for the next `weeks` weeks into
  the local cache (`replace_calendar_busy/2`). Returns `{:ok, count}`,
  `:skip`, or `{:error, reason}`.
  """
  def import_busy(%GoogleAccount{} = account, weeks \\ 8) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    time_max = DateTime.add(now, weeks * 7 * 24 * 3600, :second)

    with {:ok, account} <- ensure_fresh_token(account),
         {:ok, busy} <- client().free_busy(account.access_token, account.calendar_id, now, time_max),
         intervals = Enum.flat_map(busy, &parse_busy_interval/1),
         {:ok, count} <- Professionals.replace_calendar_busy(account.professional_id, intervals) do
      Professionals.update_google_account(account, %{"busy_synced_at" => now})
      {:ok, count}
    end
  end

  # --- Event payload ------------------------------------------------------

  defp build_event(%Appointment{} = appointment) do
    appointment = Mehungry.Repo.preload(appointment, [:client])

    base = %{
      "summary" => appointment.title || "Consultation",
      "description" => appointment.notes || "",
      "start" => %{"dateTime" => to_rfc3339(appointment.scheduled_at), "timeZone" => "UTC"},
      "end" => %{
        "dateTime" => to_rfc3339(appointment.ends_at || NaiveDateTime.add(appointment.scheduled_at, 3600)),
        "timeZone" => "UTC"
      }
    }

    base
    |> maybe_put_attendees(appointment)
    |> maybe_put_conference(appointment)
  end

  # Only request a Meet link when one hasn't already been set manually.
  defp maybe_put_conference(event, %Appointment{meeting_url: url})
       when is_binary(url) and url != "" do
    Map.put(event, "location", url)
  end

  defp maybe_put_conference(event, _appointment) do
    Map.put(event, "conferenceData", %{
      "createRequest" => %{
        "requestId" => Ecto.UUID.generate(),
        "conferenceSolutionKey" => %{"type" => "hangoutsMeet"}
      }
    })
  end

  defp maybe_put_attendees(event, %Appointment{client: %{email: email}})
       when is_binary(email) and email != "" do
    Map.put(event, "attendees", [%{"email" => email}])
  end

  defp maybe_put_attendees(event, _appointment), do: event

  defp extract_meet_url(%{"conferenceData" => %{"entryPoints" => entries}}) when is_list(entries) do
    entries
    |> Enum.find(&(&1["entryPointType"] == "video"))
    |> case do
      %{"uri" => uri} -> uri
      _ -> nil
    end
  end

  defp extract_meet_url(%{"hangoutLink" => link}) when is_binary(link), do: link
  defp extract_meet_url(_), do: nil

  # Naive UTC datetimes → RFC3339 with explicit offset.
  defp to_rfc3339(%NaiveDateTime{} = naive) do
    naive
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.to_iso8601()
  end

  defp parse_busy_interval(%{"start" => s, "end" => e}) do
    with {:ok, starts_at, _} <- DateTime.from_iso8601(s),
         {:ok, ends_at, _} <- DateTime.from_iso8601(e) do
      [%{starts_at: DateTime.truncate(starts_at, :second), ends_at: DateTime.truncate(ends_at, :second)}]
    else
      _ -> []
    end
  end

  defp parse_busy_interval(_), do: []
end
