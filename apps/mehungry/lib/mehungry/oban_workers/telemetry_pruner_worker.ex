defmodule Mehungry.ObanWorkers.TelemetryPrunerWorker do
  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger
  import Ecto.Query

  @retention_days 30

  @impl Oban.Worker
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
