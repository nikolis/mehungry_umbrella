defmodule Mehungry.Professionals.GoogleCalendar.ClientBehaviour do
  @moduledoc """
  Contract for the Google Calendar API client, so tests can swap in a stub via
  the `:google_calendar_client` config key (mirrors `:instagram_client`).

  All calls return `{:ok, result}` or
  `{:error, {:http_error, status, body} | {:transport_error, reason}}`.
  """

  @type token :: String.t()
  @type calendar_id :: String.t()
  @type event_id :: String.t()

  @doc "Exchanges a refresh token for a fresh access token (Google token endpoint)."
  @callback refresh_access_token(refresh_token :: String.t()) ::
              {:ok, map()} | {:error, term()}

  @doc "Inserts a calendar event (with a Meet conference request). Returns the created event."
  @callback insert_event(token, calendar_id, event :: map()) :: {:ok, map()} | {:error, term()}

  @doc "Patches an existing calendar event. Returns the updated event."
  @callback update_event(token, calendar_id, event_id, event :: map()) ::
              {:ok, map()} | {:error, term()}

  @doc "Deletes a calendar event. Treats a 404/410 (already gone) as success."
  @callback delete_event(token, calendar_id, event_id) :: :ok | {:error, term()}

  @doc """
  Reads busy intervals between two UTC `DateTime`s for the given calendar.
  Returns `{:ok, [%{"start" => iso8601, "end" => iso8601}]}`.
  """
  @callback free_busy(token, calendar_id, time_min :: DateTime.t(), time_max :: DateTime.t()) ::
              {:ok, [map()]} | {:error, term()}
end
