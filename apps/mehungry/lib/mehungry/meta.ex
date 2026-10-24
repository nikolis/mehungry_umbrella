defmodule Mehungry.Meta do
  @moduledoc """
  The Meta context — consent-independent, zero-PII traffic metrics.

  Everything that merely duplicated Google Analytics (per-visit tracking,
  referrer / traffic-source attribution, device/OS/browser breakdowns, session
  reconstruction, geo enrichment, and the SEO referrer analytics) was removed in
  favour of GA4 + Google Search Console, which do all of that more accurately.

  What remains is the one signal GA4 cannot provide: an anonymous,
  consent-independent count of connected sessions — the honest denominator that
  also includes visitors who declined the cookie banner. It stores only a daily
  count + total duration (see `Mehungry.Meta.DailySessionMetric`), written by
  `Mehungry.Meta.SessionAggregator` when a LiveView process dies.
  """

  import Ecto.Query, warn: false
  alias Mehungry.Repo

  alias Mehungry.Meta.DailySessionMetric

  @doc """
  IANA timezone the metrics report in, so day boundaries and daily buckets match
  the Google Analytics property timezone instead of UTC.
  """
  def reporting_timezone do
    Application.get_env(:mehungry, :reporting_timezone, "Etc/UTC")
  end

  # ---------- Anonymous session metrics (consent-independent, zero PII) ----------
  #
  # Backed by `daily_session_metrics` (date + two counters, no identifying data).
  # Written by `Mehungry.Meta.SessionAggregator` when a LiveView process dies.
  # Counts 100% of connected traffic regardless of the cookie banner, which is
  # why it stores nothing personal.

  @doc """
  Folds one finished session into the daily aggregate.

  Atomic upsert: increments `session_count` by 1 and `total_duration_seconds` by
  `duration_seconds` for the local calendar date of `started_at_utc`. The date is
  computed in Postgres (in `reporting_timezone/0`) so day boundaries match the
  dashboard without needing an Elixir tz dependency.
  """
  def record_session(%DateTime{} = started_at_utc, duration_seconds)
      when is_integer(duration_seconds) and duration_seconds >= 0 do
    tz = reporting_timezone()

    Repo.query!(
      """
      INSERT INTO daily_session_metrics (date, session_count, total_duration_seconds, inserted_at, updated_at)
      VALUES (($1 AT TIME ZONE 'UTC' AT TIME ZONE $2)::date, 1, $3, now(), now())
      ON CONFLICT (date) DO UPDATE SET
        session_count = daily_session_metrics.session_count + 1,
        total_duration_seconds = daily_session_metrics.total_duration_seconds + EXCLUDED.total_duration_seconds,
        updated_at = now()
      """,
      [started_at_utc, tz, duration_seconds]
    )

    :ok
  end

  @doc """
  Per-day session aggregates for the last `days` days (oldest → newest), each
  with a computed `avg_seconds` (0 when no sessions).
  """
  def session_metrics_per_day(days \\ 14) do
    cutoff = Date.add(Date.utc_today(), -days)

    from(m in DailySessionMetric,
      where: m.date >= ^cutoff,
      order_by: [asc: m.date]
    )
    |> Repo.all()
    |> Enum.map(fn m ->
      %{
        date: m.date,
        session_count: m.session_count,
        total_duration_seconds: m.total_duration_seconds,
        avg_seconds: avg_seconds(m.total_duration_seconds, m.session_count)
      }
    end)
  end

  @doc """
  Today's session aggregate in the reporting timezone — `%{sessions, total_seconds, avg_seconds}`
  (all zero when nothing has been recorded today).
  """
  def session_metrics_today do
    tz = reporting_timezone()

    row =
      from(m in DailySessionMetric,
        where:
          m.date == fragment("(now() AT TIME ZONE ?)::date", ^tz),
        select: %{sessions: m.session_count, total_seconds: m.total_duration_seconds}
      )
      |> Repo.one()

    case row do
      nil ->
        %{sessions: 0, total_seconds: 0, avg_seconds: 0}

      %{sessions: sessions, total_seconds: total} ->
        %{sessions: sessions, total_seconds: total, avg_seconds: avg_seconds(total, sessions)}
    end
  end

  @doc """
  All-time session-metrics summary — `%{sessions_total, first_day, last_day,
  avg_seconds}` (the §5.2 "post-deploy" traffic query in `docs/app_status.md`,
  the consent-independent denominator GA4 cannot see). Days with no sessions are
  simply absent; `first_day`/`last_day` are `nil` when the table is empty.
  """
  def session_metrics_summary do
    from(m in DailySessionMetric,
      select: %{
        sessions_total: coalesce(sum(m.session_count), 0),
        duration_total: coalesce(sum(m.total_duration_seconds), 0),
        first_day: min(m.date),
        last_day: max(m.date)
      }
    )
    |> Repo.one()
    |> then(fn %{sessions_total: sessions, duration_total: duration} = row ->
      # `sum(...)` comes back as `Decimal`; normalize to plain integers.
      sessions = to_int(sessions)
      duration = to_int(duration)

      row
      |> Map.delete(:duration_total)
      |> Map.put(:sessions_total, sessions)
      |> Map.put(:avg_seconds, avg_seconds(duration, sessions))
    end)
  end

  defp to_int(%Decimal{} = d), do: Decimal.to_integer(d)
  defp to_int(n) when is_integer(n), do: n
  defp to_int(_), do: 0

  defp avg_seconds(_total, 0), do: 0
  defp avg_seconds(total, count), do: div(total, count)
end
