defmodule Mehungry.ObanWorkers.ResearchIngestionWorker do
  @moduledoc """
  One job == **one condition** of an admin-triggered research-ingestion run (the
  UI control for `mix research.ingest`). It sends the condition's studies to the
  `mehungry_extractor` `/analyze` and stores the result via the shared
  `Mehungry.Literature.ResearchIngestion.analyze_condition/2`, then reports its
  outcome into the run's `ResearchIngestionRun` row (`record_condition/2`).

  **Fan-out, not a single mega-job** — so a server restart only interrupts the
  one condition in flight (Oban rescues + retries it via `Lifeline`), while the
  other conditions are independent queued jobs that resume on boot. Runs on
  `:imports` (concurrency 1 → effectively sequential, which is what we want for
  the one extractor). `max_attempts: 3`: a transient extractor failure retries
  (ingestion is idempotent — a re-run skips already-analyzed studies); on the
  **final** attempt the condition is recorded as failed so the run can still
  finalize (a few bad conditions can't wedge it).
  """

  use Oban.Worker, queue: :imports, max_attempts: 3

  require Logger

  alias Mehungry.Health
  alias Mehungry.Literature.ResearchIngestion
  alias Mehungry.Literature.ResearchIngestionRuns, as: Runs

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    run_id = args["run_id"]
    condition_id = args["condition_id"]
    opts = [crawl: args["crawl"], force: args["force"], batch: args["batch"]]

    name = condition_name(condition_id)
    Runs.start_condition(run_id, name)

    case ResearchIngestion.analyze_condition(condition_id, opts) do
      {:ok, counts, target_count} ->
        Logger.info(
          "[ResearchIngestion] #{name} (##{condition_id}): #{target_count} analyzed " <>
            "(#{counts.inserted} new, #{counts.updated} updated)"
        )

        Runs.record_condition(run_id, counts)
        :ok

      {:error, reason} ->
        if job.attempt >= job.max_attempts do
          # Out of retries — record the condition as failed so the run finalizes.
          Logger.warning(
            "[ResearchIngestion] #{name} (##{condition_id}) failed after " <>
              "#{job.attempt} attempts: #{inspect(reason)}"
          )

          Runs.record_condition_failure(run_id, reason)
          :ok
        else
          # Let Oban retry (extractor may be transiently unreachable).
          {:error, reason}
        end
    end
  end

  defp condition_name(condition_id) do
    case Health.get_condition(condition_id) do
      %{name: name} -> name
      _ -> "condition ##{condition_id}"
    end
  end
end
