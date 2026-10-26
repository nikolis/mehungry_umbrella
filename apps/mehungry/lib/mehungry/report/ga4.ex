defmodule Mehungry.Report.GA4 do
  @moduledoc """
  Minimal read-only client for the Google Analytics Data API (GA4) `runReport`
  endpoint — the §7.2 automation in `docs/implementation/app_status.md`.

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
      dc_cities = datacenter_cities()

      {:ok,
       %{
         window_days: days,
         datacenter_cities: dc_cities,
         totals: totals(property, token, range),
         bot_totals: totals(property, token, range, city_filter(dc_cities)),
         channels: by_dimension(property, token, range, "sessionDefaultChannelGroup", "sessions", 8),
         countries: by_dimension(property, token, range, "country", "sessions", 5),
         cities: by_dimension(property, token, range, "city", "sessions", 15),
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

  defp totals(property, token, range, extra \\ %{}) do
    body =
      Map.merge(
        %{
          "dateRanges" => range,
          "metrics" => [
            %{"name" => "sessions"},
            %{"name" => "activeUsers"},
            %{"name" => "newUsers"},
            %{"name" => "engagementRate"},
            %{"name" => "averageSessionDuration"},
            # engagedSessions = sessions that lasted >10s OR had 2+ views OR a
            # conversion (GA4's own definition). sessions - engagedSessions is
            # therefore the "<10s, single-view" bot-like bucket.
            %{"name" => "engagedSessions"}
          ]
        },
        extra
      )

    case run_report(property, token, body) do
      {:ok, %{"rows" => [%{"metricValues" => values} | _]}} ->
        [sessions, active, new, eng_rate, avg_dur, engaged] = Enum.map(values, & &1["value"])

        %{
          sessions: to_int(sessions),
          active_users: to_int(active),
          new_users: to_int(new),
          engagement_rate: to_float(eng_rate),
          avg_session_seconds: round(to_float(avg_dur)),
          engaged_sessions: to_int(engaged)
        }

      {:ok, _} ->
        %{
          sessions: 0,
          active_users: 0,
          new_users: 0,
          engagement_rate: 0.0,
          avg_session_seconds: 0,
          engaged_sessions: 0
        }

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

  # GA4 already drops *known* bots, but crawler/noise traffic that evades that
  # filter is the bulk of this tiny app's sessions. We DON'T filter by country
  # (that would wrongly discard legitimate users abroad). Instead we flag two
  # reliable infrastructure/behaviour tells:
  #
  #   1. Datacenter cities — sessions geolocating to hyperscaler datacenter
  #      towns (Ashburn, The Dalles, Boardman, Council Bluffs…) are near-certain
  #      hosting/crawler traffic, not residential users. We run the totals a
  #      second time filtered to this city denylist to get an exact bot count.
  #      Curate the list from the `cities:` breakdown the report prints — add a
  #      city once you've confirmed it's a datacenter town, never a real market.
  #   2. Non-engaged / <10s sessions — see `engagedSessions` in `totals/4`.
  #
  # Override the denylist with `config :mehungry, :ga4_datacenter_cities, [...]`.
  # City values must match GA4's `city` dimension labels exactly.
  # Exact GA4 `city` labels. Most noise here is Meta/Facebook link-preview
  # crawlers (the app auto-posts recipe URLs to Facebook), which geolocate to
  # Meta's datacenter towns — hence the Prineville/Forest City/Luleå/Altoona
  # cluster. Deliberately excludes ambiguous real cities (Dublin, Springfield,
  # Fort Worth) even though they host datacenters, to avoid dropping humans.
  @default_datacenter_cities [
    # AWS / Google / Azure
    "Ashburn",
    "Boardman",
    "The Dalles",
    "Council Bluffs",
    "Moncks Corner",
    "Quincy",
    # Meta / Facebook datacenter towns (dominant source of this app's crawler noise)
    "Prineville",
    "Forest City",
    "Lulea",
    "Altoona",
    "Gallatin",
    "New Albany",
    "Eagle Mountain",
    "Papillion",
    "Huntsville",
    "Sarpy County"
  ]

  def datacenter_cities do
    case Application.get_env(:mehungry, :ga4_datacenter_cities) do
      [_ | _] = list -> list
      _ -> @default_datacenter_cities
    end
  end

  defp city_filter(cities) do
    %{
      "dimensionFilter" => %{
        "filter" => %{
          "fieldName" => "city",
          "inListFilter" => %{"values" => cities}
        }
      }
    }
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
