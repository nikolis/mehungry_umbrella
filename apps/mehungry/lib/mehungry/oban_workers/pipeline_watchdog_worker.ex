defmodule Mehungry.ObanWorkers.PipelineWatchdogWorker do
  @moduledoc """
  Cron heartbeat that resumes a wedged scientific-pipeline run of any stage.

  Every pipeline chain (crawl, annotation, candidate derivation, recommendation
  derivation) is single-threaded and self-re-enqueueing, so if its one live job
  ever vanishes without a successor (crash / node kill / deploy mid-batch / a job
  discarded after exhausting its retries) the run strands in `processing` and
  nothing picks it back up until the next server boot. This worker is the online
  safety net: every tick it hands off to
  `Mehungry.Science.PipelineWatchdog.resume_stalled/1`, which re-enqueues a batch
  for any stalled run and lets the stage worker resume or complete it.

  Idempotent and cheap: a healthy run's job is `executing`/`scheduled` (counts as
  live) so it is skipped; a stalled run is only resumed once because the batch it
  enqueues immediately becomes the live job the next tick sees. Scheduled every
  10 minutes in `config/config.exs`.
  """

  use Oban.Worker, queue: :imports, max_attempts: 1

  require Logger

  alias Mehungry.Science.PipelineWatchdog

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    case PipelineWatchdog.resume_stalled() do
      0 -> :ok
      n -> Logger.info("PipelineWatchdogWorker: resumed #{n} stalled pipeline run(s)")
    end

    :ok
  end
end
