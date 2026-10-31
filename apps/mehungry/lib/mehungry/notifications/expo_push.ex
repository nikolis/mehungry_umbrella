defmodule Mehungry.Notifications.ExpoPush do
  @moduledoc """
  Real `ExpoPushClient` — POSTs messages to the Expo push service
  (`https://exp.host/--/api/v2/push/send`). An optional `EXPO_ACCESS_TOKEN`
  (config `:expo_access_token`) is sent as a bearer when Expo's
  "enhanced security" is enabled; it's omitted otherwise.

  See `docs/implementation/notifications_system.md` §7.
  """
  @behaviour Mehungry.Notifications.ExpoPushClient

  @endpoint "https://exp.host/--/api/v2/push/send"
  @timeout_ms 10_000

  @impl true
  def push([]), do: {:ok, []}

  def push(messages) when is_list(messages) do
    body = Jason.encode!(messages)

    case HTTPoison.post(@endpoint, body, headers(), recv_timeout: @timeout_ms, timeout: @timeout_ms) do
      {:ok, %HTTPoison.Response{status_code: status, body: resp}} when status in 200..299 ->
        case Jason.decode(resp) do
          # Expo wraps the tickets in a top-level "data" array (one per message).
          {:ok, %{"data" => tickets}} when is_list(tickets) -> {:ok, tickets}
          {:ok, other} -> {:error, {:unexpected_response, other}}
          {:error, _} -> {:error, {:bad_json, resp}}
        end

      {:ok, %HTTPoison.Response{status_code: status, body: resp}} ->
        {:error, {:http_error, status, resp}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, {:transport_error, reason}}
    end
  end

  defp headers do
    base = [
      {"Content-Type", "application/json"},
      {"Accept", "application/json"},
      {"Accept-Encoding", "gzip, deflate"}
    ]

    case Application.get_env(:mehungry, :expo_access_token) do
      token when is_binary(token) and token != "" -> [{"Authorization", "Bearer " <> token} | base]
      _ -> base
    end
  end
end
