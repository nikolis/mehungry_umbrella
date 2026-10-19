defmodule Mehungry.Report.SearchConsole do
  @moduledoc """
  Read-only client for the Google Search Console API (`searchAnalytics.query`) —
  the organic-search leading indicator the app-status snapshot cares about most
  (`docs/app_status.md`: Search Console impressions on `/foods` are "the first
  sign organic is starting").

  Uses the **same service account** as GA4 (`GA4_SA_KEY` via
  `Mehungry.Report.GoogleAuth`) — it just needs a second grant + a site URL:

    * In Google Cloud, also enable the **Search Console API** on the project.
    * In Search Console → Settings → Users and permissions, add the
      service-account email (at least **Restricted**).
    * Set `GSC_SITE_URL` to the exact property id — a domain property is
      `sc-domain:m3hungry.com`, a URL-prefix property is
      `https://www.m3hungry.com/`.

  When `GSC_SITE_URL` is unset, `fetch/1` returns `{:skip, _}`. Search Console
  data lags ~2-3 days, so the most recent day(s) in the window may be empty.
  """

  require Logger

  alias Mehungry.Report.GoogleAuth

  @api "https://searchconsole.googleapis.com/webmasters/v3/sites"
  @scope "https://www.googleapis.com/auth/webmasters.readonly"
  @timeout_ms 20_000

  @doc """
  Pulls Search Console metrics for the last `days` days (default 28): overall
  clicks/impressions/CTR/position, the `/foods` subset (the organic leading
  indicator), top queries and top pages.

  Returns `{:ok, map}`, `{:skip, reason}` (not configured), or `{:error, reason}`.
  """
  def fetch(days \\ 28) do
    with {:ok, creds} <- GoogleAuth.credentials(),
         {:ok, site} <- site_url(),
         {:ok, token} <- GoogleAuth.access_token(creds, @scope) do
      today = Date.utc_today()
      start = Date.add(today, -days)
      base = %{"startDate" => Date.to_iso8601(start), "endDate" => Date.to_iso8601(today)}

      {:ok,
       %{
         window_days: days,
         totals: totals(site, token, base),
         foods: totals(site, token, Map.put(base, "dimensionFilterGroups", foods_filter())),
         top_queries: dimension(site, token, base, "query", 5),
         top_pages: dimension(site, token, base, "page", 8)
       }}
    else
      {:skip, _} = skip -> skip
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "True when the SA key and a site URL are both configured."
  def configured?, do: match?({:ok, _}, GoogleAuth.credentials()) and match?({:ok, _}, site_url())

  defp foods_filter do
    [%{"filters" => [%{"dimension" => "page", "operator" => "contains", "expression" => "/foods"}]}]
  end

  defp totals(site, token, body) do
    case query(site, token, body) do
      {:ok, %{"rows" => [row | _]}} -> row_metrics(row)
      {:ok, _} -> %{clicks: 0, impressions: 0, ctr: 0.0, position: 0.0}
      {:error, reason} -> %{error: reason}
    end
  end

  defp dimension(site, token, base, dimension, limit) do
    body = base |> Map.put("dimensions", [dimension]) |> Map.put("rowLimit", limit)

    case query(site, token, body) do
      {:ok, %{"rows" => rows}} when is_list(rows) ->
        Enum.map(rows, fn row ->
          %{label: row |> Map.get("keys", []) |> List.first()}
          |> Map.merge(row_metrics(row))
        end)

      {:ok, _} ->
        []

      {:error, reason} ->
        [%{label: "(error)", error: reason}]
    end
  end

  defp row_metrics(row) do
    %{
      clicks: round(num(row["clicks"])),
      impressions: round(num(row["impressions"])),
      ctr: round_to(num(row["ctr"]) * 100, 2),
      position: round_to(num(row["position"]), 1)
    }
  end

  # Float.round/2 only accepts floats; GSC returns bare integers (e.g. 0) when a
  # metric is zero. Coerce to float first.
  defp round_to(n, precision), do: Float.round(n * 1.0, precision)

  defp query(site, token, body) do
    url = "#{@api}/#{URI.encode_www_form(site)}/searchAnalytics/query"

    headers = [
      {"Authorization", "Bearer #{token}"},
      {"Content-Type", "application/json"},
      {"Accept", "application/json"}
    ]

    case HTTPoison.post(url, Jason.encode!(body), headers, recv_timeout: @timeout_ms) do
      {:ok, %HTTPoison.Response{status_code: 200, body: resp}} ->
        Jason.decode(resp)

      {:ok, %HTTPoison.Response{status_code: status, body: resp}} ->
        Logger.warning("[SearchConsole] query HTTP #{status}: #{resp}")
        {:error, "HTTP #{status}: #{String.slice(resp, 0, 300)}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, {:transport_error, reason}}
    end
  end

  defp site_url do
    case Application.get_env(:mehungry, :gsc_site_url) do
      url when is_binary(url) and url != "" -> {:ok, url}
      _ -> {:skip, "GSC_SITE_URL not set"}
    end
  end

  defp num(n) when is_number(n), do: n
  defp num(_), do: 0
end
