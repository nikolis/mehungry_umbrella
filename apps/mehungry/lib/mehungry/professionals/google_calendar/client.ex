defmodule Mehungry.Professionals.GoogleCalendar.Client do
  @moduledoc """
  HTTP client for the Google Calendar API v3 (per-nutritionist OAuth tokens).

  Uses the `calendar.events` scope to create/update/delete events (minting a
  Google Meet link via `conferenceData.createRequest`) and the
  `calendar.readonly`/freebusy scope to import busy intervals. OAuth refresh goes
  through the standard Google token endpoint with the app's web client
  credentials (shared with `ueberauth_google`).

  All calls return `{:ok, result}` or
  `{:error, {:http_error, status, body} | {:transport_error, reason}}`.
  """

  @behaviour Mehungry.Professionals.GoogleCalendar.ClientBehaviour

  require Logger

  @token_uri "https://oauth2.googleapis.com/token"
  @api_base "https://www.googleapis.com/calendar/v3"
  @timeout_ms 20_000

  @impl true
  def refresh_access_token(refresh_token) do
    form = [
      {"grant_type", "refresh_token"},
      {"refresh_token", refresh_token},
      {"client_id", client_id()},
      {"client_secret", client_secret()}
    ]

    @token_uri
    |> HTTPoison.post({:form, form}, [], recv_timeout: @timeout_ms)
    |> handle_response("refresh_access_token")
  end

  @impl true
  def insert_event(token, calendar_id, event) do
    path = "/calendars/#{URI.encode_www_form(calendar_id)}/events?conferenceDataVersion=1"
    post_json(path, "insert_event", token, event)
  end

  @impl true
  def update_event(token, calendar_id, event_id, event) do
    path =
      "/calendars/#{URI.encode_www_form(calendar_id)}/events/#{URI.encode_www_form(event_id)}?conferenceDataVersion=1"

    request_json(:patch, path, "update_event", token, event)
  end

  @impl true
  def delete_event(token, calendar_id, event_id) do
    path = "/calendars/#{URI.encode_www_form(calendar_id)}/events/#{URI.encode_www_form(event_id)}"

    (@api_base <> path)
    |> HTTPoison.delete(auth_headers(token), recv_timeout: @timeout_ms)
    |> case do
      {:ok, %HTTPoison.Response{status_code: status}} when status in [200, 204, 404, 410] ->
        :ok

      {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
        Logger.error("[GoogleCalendar] delete_event: HTTP #{status} — #{inspect(body)}")
        {:error, {:http_error, status, body}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, {:transport_error, reason}}
    end
  end

  @impl true
  def free_busy(token, calendar_id, %DateTime{} = time_min, %DateTime{} = time_max) do
    body = %{
      "timeMin" => DateTime.to_iso8601(time_min),
      "timeMax" => DateTime.to_iso8601(time_max),
      "items" => [%{"id" => calendar_id}]
    }

    with {:ok, decoded} <- post_json("/freeBusy", "free_busy", token, body) do
      busy =
        decoded
        |> get_in(["calendars", calendar_id, "busy"])
        |> List.wrap()

      {:ok, busy}
    end
  end

  # --- HTTP plumbing ------------------------------------------------------

  defp post_json(path, op, token, body), do: request_json(:post, path, op, token, body)

  defp request_json(method, path, op, token, body) do
    headers = [{"Content-Type", "application/json"} | auth_headers(token)]
    url = @api_base <> path
    payload = Jason.encode!(body)

    HTTPoison.request(method, url, payload, headers, recv_timeout: @timeout_ms)
    |> handle_response(op)
  end

  defp auth_headers(token) do
    [{"Authorization", "Bearer #{token}"}, {"Accept", "application/json"}]
  end

  defp handle_response({:ok, %HTTPoison.Response{status_code: status, body: body}}, _op)
       when status in 200..299 do
    case Jason.decode(body) do
      {:ok, decoded} -> {:ok, decoded}
      # Some successful calls (e.g. 204) have an empty body.
      {:error, _} -> {:ok, %{}}
    end
  end

  defp handle_response({:ok, %HTTPoison.Response{status_code: status, body: body}}, op) do
    decoded =
      case Jason.decode(body) do
        {:ok, map} -> map
        {:error, _} -> body
      end

    Logger.error("[GoogleCalendar] #{op}: HTTP #{status} — #{inspect(decoded)}")
    {:error, {:http_error, status, decoded}}
  end

  defp handle_response({:error, %HTTPoison.Error{reason: reason}}, op) do
    Logger.error("[GoogleCalendar] #{op}: transport error — #{inspect(reason)}")
    {:error, {:transport_error, reason}}
  end

  defp client_id do
    Application.get_env(:ueberauth, Ueberauth.Strategy.Google.OAuth)[:client_id]
  end

  defp client_secret do
    Application.get_env(:ueberauth, Ueberauth.Strategy.Google.OAuth)[:client_secret]
  end
end
