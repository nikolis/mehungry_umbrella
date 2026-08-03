defmodule Mehungry.Telemetry.RequestRate do
  @moduledoc """
  Request-rate reporting over the telemetry the app already collects.

  Every HTTP request emits `[:phoenix, :router_dispatch, :stop]`, which
  `Mehungry.Telemetry.MetricsBuffer` records as `"phoenix.request.duration"`
  tagged by `route`, aggregated into 5-minute `Mehungry.Telemetry.Snapshot`
  rows (each carrying a `sample_count`). This module reads those rows back as a
  requests-per-minute view, scoped to the token-guarded LocalAi REST API
  (`/api/local_ai/*`), and augments them with a live count from the in-memory
  buffer for a "right now" figure.
  """

  import Ecto.Query

  alias Mehungry.Repo
  alias Mehungry.Telemetry.{MetricsBuffer, Snapshot}

  @metric "phoenix.request.duration"
  @route_prefix "/api/local_ai"

  @doc "The route prefix these rates are scoped to (`#{@route_prefix}`)."
  def route_prefix, do: @route_prefix

  @doc """
  Requests-per-minute summary for the LocalAi REST API over the trailing
  `window_seconds` (default 1h).

  Returns a map with:

    * `:routes` — one entry per `#{@route_prefix}/*` route seen in the window,
      each with `:requests` (total over the window), `:per_min` (window
      average), `:latest_5m_per_min` (the newest 5-min snapshot's rate — the
      closest thing to "current" from history), and `:avg_ms`;
    * `:total` — the same `:requests`/`:per_min` rolled up across routes;
    * `:live` — requests counted in the in-memory buffer since the last 5-min
      flush and the per-minute rate they imply (`nil` before the first flush).

  `:generated_at` is an ISO-8601 string so the result serializes as JSON
  without depending on an encoder for `DateTime`.
  """
  def local_ai(window_seconds \\ 3600) when is_integer(window_seconds) and window_seconds > 0 do
    now = DateTime.utc_now()
    cutoff = DateTime.add(now, -window_seconds, :second)

    routes =
      Repo.all(
        from(s in Snapshot,
          where: s.metric == ^@metric,
          where: s.period_start >= ^cutoff,
          where: fragment("?->>'route' LIKE ?", s.tags, ^(@route_prefix <> "/%"))
        )
      )
      |> Enum.group_by(& &1.tags["route"])
      |> Enum.map(fn {route, rows} -> route_summary(route, rows, window_seconds) end)
      |> Enum.sort_by(& &1.requests, :desc)

    %{
      route_prefix: @route_prefix,
      window_seconds: window_seconds,
      generated_at: DateTime.to_iso8601(now),
      routes: routes,
      total: total_summary(routes, window_seconds),
      live: live_summary()
    }
  end

  defp route_summary(route, rows, window_seconds) do
    requests = rows |> Enum.map(& &1.sample_count) |> Enum.sum()
    latest = rows |> Enum.sort_by(& &1.period_start, {:desc, DateTime}) |> List.first()

    %{
      route: route,
      requests: requests,
      per_min: per_min(requests, window_seconds),
      latest_5m_per_min: Float.round(latest.sample_count / 5, 3),
      avg_ms: weighted_avg_ms(rows)
    }
  end

  defp total_summary(routes, window_seconds) do
    requests = routes |> Enum.map(& &1.requests) |> Enum.sum()
    %{requests: requests, per_min: per_min(requests, window_seconds)}
  end

  defp live_summary do
    counts = MetricsBuffer.live_route_counts(@metric, @route_prefix)
    elapsed_ms = MetricsBuffer.since_last_flush_ms()
    requests = counts |> Map.values() |> Enum.sum()

    per_min =
      case elapsed_ms do
        ms when is_integer(ms) and ms > 0 -> Float.round(requests / (ms / 60_000), 3)
        _ -> nil
      end

    %{
      since_last_flush_seconds: if(is_integer(elapsed_ms), do: div(elapsed_ms, 1000)),
      requests: requests,
      per_min: per_min,
      by_route: counts
    }
  end

  # Sample-count-weighted mean of each window's avg latency (nil avgs ignored),
  # rounded to 2 dp; nil when no window carried a latency.
  defp weighted_avg_ms(rows) do
    {sum, count} =
      Enum.reduce(rows, {0.0, 0}, fn
        %{avg: avg, sample_count: n}, {sum, count} when is_number(avg) ->
          {sum + avg * n, count + n}

        _row, acc ->
          acc
      end)

    if count > 0, do: Float.round(sum / count, 2)
  end

  @doc """
  Converts a raw request `count` over `window_seconds` into a per-minute rate,
  rounded to 3 dp.

  ## Examples

      iex> Mehungry.Telemetry.RequestRate.per_min(120, 3600)
      2.0

      iex> Mehungry.Telemetry.RequestRate.per_min(0, 3600)
      0.0

  """
  def per_min(count, window_seconds) when window_seconds > 0 do
    Float.round(count / (window_seconds / 60), 3)
  end
end
