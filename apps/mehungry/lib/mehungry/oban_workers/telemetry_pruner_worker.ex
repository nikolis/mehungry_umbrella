defmodule Mehungry.ObanWorkers.TelemetryPrunerWorker do
  @moduledoc """
  Daily Oban cron worker (`0 3 * * *`, see `config/config.exs`) that enforces
  the 30-day retention policy described in `docs/observability.md`.

  Deletes rows older than 30 days from the three tables written by
  `Mehungry.Telemetry.MetricsBuffer` and the DIY error tracker:

    * `telemetry_snapshots` (`Mehungry.Telemetry.Snapshot`) — pruned by `period_start`
    * `error_events` (`Mehungry.Telemetry.ErrorEvent`) — pruned by `last_seen`, so a
      recurring error stays alive for as long as it keeps occurring
    * `query_time_profiles` (`Mehungry.Telemetry.QueryProfile`) — pruned by `period_start`

  The retention window is a module attribute (`@retention_days`), not runtime
  configuration — there is no environment variable or admin setting for it.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger
  import Ecto.Query

  @retention_days 30

  @impl Oban.Worker
  @doc """
  Deletes snapshot, error-event, and query-profile rows whose retention
  timestamp is older than #{@retention_days} days, logs the counts removed,
  and always returns `:ok`.
  """
  def perform(_job) do
    cutoff = DateTime.add(DateTime.utc_now(), -@retention_days * 86_400, :second)

    {count, _} =
      Mehungry.Repo.delete_all(
        from s in Mehungry.Telemetry.Snapshot,
          where: s.period_start < ^cutoff
      )

    {error_count, _} =
      Mehungry.Repo.delete_all(
        from e in Mehungry.Telemetry.ErrorEvent,
          where: e.last_seen < ^cutoff
      )

    {query_count, _} =
      Mehungry.Repo.delete_all(
        from p in Mehungry.Telemetry.QueryProfile,
          where: p.period_start < ^cutoff
      )

    Logger.info(
      "[TelemetryPrunerWorker] Deleted #{count} snapshots, #{error_count} error events and " <>
        "#{query_count} query profiles older than #{@retention_days} days"
    )

    :ok
  end
end
