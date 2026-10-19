defmodule Mehungry.Report.GA4 do
  @moduledoc """
  Minimal read-only client for the Google Analytics Data API (GA4) `runReport`
  endpoint — the §7.2 automation in `docs/app_status.md`.

  GA4 is otherwise unreadable from the codebase (the app only *sends* events via
  gtag). To enable this client, provision a Google service account with the
  **Analytics Data API** enabled, add its email as a **Viewer** on the GA4
  property, and set two env vars:

    * `GA4_SA_KEY`      — the service-account JSON key, either inline (the raw
                          JSON string) or a path to the `.json` file on disk.
    * `GA4_PROPERTY_ID` — the numeric GA4 property id (digits only, no `properties/`).

  When either is missing, `fetch/1` returns `{:skip, reason}` so the snapshot
  degrades gracefully (you paste GA4 figures by hand) instead of failing.

  The service-account JWT is signed with Erlang's built-in `:public_key` (RS256),
  so no JWT dependency is needed.
  """

  require Logger

  alias Mehungry.Report.GoogleAuth

  @data_api "https://analyticsdata.googleapis.com/v1beta"
  @scope "https://www.googleapis.com/auth/analytics.readonly"
  @timeout_ms 20_000

  @doc """
  Pulls the §5.3 GA4 figures for the last `days` days (default 28):
  overall metrics + acquisition-by-channel + top countries + top pages.

  Returns `{:ok, map}`, `{:skip, reason}` (not configured), or `{:error, reason}`.
  """
  def fetch(days \\ 28) do
    with {:ok, creds} <- GoogleAuth.credentials(),
         {:ok, property} <- property_id(),
         {:ok, token} <- GoogleAuth.access_token(creds, @scope) do
      range = [%{"startDate" => "#{days}daysAgo", "endDate" => "today"}]

      {:ok,
       %{
         window_days: days,
         totals: totals(property, token, range),
         channels: by_dimension(property, token, range, "sessionDefaultChannelGroup", "sessions", 8),
         countries: by_dimension(property, token, range, "country", "sessions", 5),
         pages: by_dimension(property, token, range, "pagePath", "screenPageViews", 8)
       }}
    else
      {:skip, _} = skip -> skip
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "True when both GA4 env vars are present."
  def configured?, do: match?({:ok, _}, GoogleAuth.credentials()) and match?({:ok, _}, property_id())

  # ---------------------------------------------------------------------------
  # Reports
  # ---------------------------------------------------------------------------

  defp totals(property, token, range) do
    body = %{
      "dateRanges" => range,
      "metrics" => [
        %{"name" => "sessions"},
        %{"name" => "activeUsers"},
        %{"name" => "newUsers"},
        %{"name" => "engagementRate"},
        %{"name" => "averageSessionDuration"}
      ]
    }

    case run_report(property, token, body) do
      {:ok, %{"rows" => [%{"metricValues" => values} | _]}} ->
        [sessions, active, new, eng_rate, avg_dur] = Enum.map(values, & &1["value"])

        %{
          sessions: to_int(sessions),
          active_users: to_int(active),
          new_users: to_int(new),
          engagement_rate: to_float(eng_rate),
          avg_session_seconds: round(to_float(avg_dur))
        }

      {:ok, _} ->
        %{sessions: 0, active_users: 0, new_users: 0, engagement_rate: 0.0, avg_session_seconds: 0}

      {:error, reason} ->
        %{error: reason}
    end
  end

  defp by_dimension(property, token, range, dimension, metric, limit) do
    body = %{
      "dateRanges" => range,
      "dimensions" => [%{"name" => dimension}],
      "metrics" => [%{"name" => metric}],
      "limit" => limit,
      "orderBys" => [%{"metric" => %{"metricName" => metric}, "desc" => true}]
    }

    case run_report(property, token, body) do
      {:ok, %{"rows" => rows}} when is_list(rows) ->
        Enum.map(rows, fn row ->
          %{
            label: row |> Map.get("dimensionValues", []) |> List.first() |> value_of(),
            value: row |> Map.get("metricValues", []) |> List.first() |> value_of() |> to_int()
          }
        end)

      {:ok, _} ->
        []

      {:error, reason} ->
        [%{label: "(error)", value: 0, error: reason}]
    end
  end

  defp run_report(property, token, body) do
    url = "#{@data_api}/properties/#{property}:runReport"

    headers = [
      {"Authorization", "Bearer #{token}"},
      {"Content-Type", "application/json"},
      {"Accept", "application/json"}
    ]

    case HTTPoison.post(url, Jason.encode!(body), headers, recv_timeout: @timeout_ms) do
      {:ok, %HTTPoison.Response{status_code: 200, body: resp}} ->
        Jason.decode(resp)

      {:ok, %HTTPoison.Response{status_code: status, body: resp}} ->
        Logger.warning("[GA4] runReport HTTP #{status}: #{resp}")
        {:error, "HTTP #{status}: #{String.slice(resp, 0, 300)}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, {:transport_error, reason}}
    end
  end

  # ---------------------------------------------------------------------------
  # Config
  # ---------------------------------------------------------------------------

  defp property_id do
    case Application.get_env(:mehungry, :ga4_property_id) do
      id when is_binary(id) and id != "" -> {:ok, String.replace(id, ~r/\D/, "")}
      _ -> {:skip, "GA4_PROPERTY_ID not set"}
    end
  end

  defp value_of(%{"value" => v}), do: v
  defp value_of(_), do: nil

  defp to_int(nil), do: 0
  defp to_int(v) when is_integer(v), do: v

  defp to_int(v) when is_binary(v) do
    case Integer.parse(v) do
      {n, _} -> n
      :error -> 0
    end
  end

  defp to_float(nil), do: 0.0
  defp to_float(v) when is_float(v), do: v
  defp to_float(v) when is_integer(v), do: v * 1.0

  defp to_float(v) when is_binary(v) do
    case Float.parse(v) do
      {n, _} -> n
      :error -> 0.0
    end
  end
end
