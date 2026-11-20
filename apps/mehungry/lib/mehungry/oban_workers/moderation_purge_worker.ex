defmodule Mehungry.ObanWorkers.ModerationPurgeWorker do
  @moduledoc """
  Daily cron (`config/config.exs`) that deletes moderation reports resolved more
  than 12 months ago — the retention limit promised in the privacy policy.
  Open reports are never touched. Idempotent.
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    count = Mehungry.Moderation.purge_resolved_reports()
    if count > 0, do: Logger.info("Moderation purge: deleted #{count} resolved report(s)")
    :ok
  end
end
