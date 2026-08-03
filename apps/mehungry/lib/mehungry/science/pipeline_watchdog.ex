defmodule Mehungry.Science.PipelineWatchdog do
  @moduledoc """
  Online recovery for a wedged scientific-pipeline run — the live counterpart to
  `Mehungry.Science.RunReconciler`.

  Every operable stage (literature crawl, PubTator annotation, compound-candidate
  derivation, recommendation-candidate derivation) advances through a
  *single-threaded* chain: one Oban job processes a batch and enqueues its own
  successor, and the run is only `completed` when the worker sees an empty batch.
  That terminates cleanly — as long as the chain keeps advancing. If the one live
  job ever disappears without a successor (a hard crash / OOM / node kill / deploy
  mid-batch, or a job that exhausts its retries and goes `discarded`), the run is
  stranded in `processing`: nothing re-enqueues, the remaining work never runs, and
  `/professional/science` keeps that stage's Run button disabled because its
  `running?/1` guard is still true.

  `RunReconciler` only heals this at boot (and by marking the run `failed`). A
  long-lived production node needs an *online* sweep, which is this module: run
  periodically (see `Mehungry.ObanWorkers.PipelineWatchdogWorker`), it finds every
  run — across all four stages — that is non-terminal, has had no progress for
  `grace_seconds`, and has **no live Oban job** pointing at it, and simply
  re-enqueues a first batch for it. The stage worker takes it from there: it
  resumes where the chain broke (already-ledgered work is skipped, so this is
  idempotent) or marks the run `completed` if there is nothing left to do.

  A run whose job is genuinely in-flight — `executing`, or `scheduled` because it
  is snoozing on an NCBI rate limit — is left strictly alone: those states count
  as live, so a slow-but-healthy run is never disturbed. The grace window keeps us
  from racing a job that just finished a batch and is about to enqueue its
  successor.

  Poison pills (a single item that fails *every* attempt) are handled at the
  source in the crawl/annotation workers, not here — otherwise a resumed run would
  just re-hit the pill and be discarded again each tick. This watchdog only
  recovers a chain that broke leaving *nothing* enqueued.
  """

  import Ecto.Query, warn: false

  require Logger

  alias Mehungry.Repo

  # {run table, self-re-enqueueing stage worker}. Same stage set as RunReconciler.
  @stages [
    {"literature_crawl_runs", Mehungry.ObanWorkers.LiteratureCrawlWorker},
    {"pubtator_annotation_runs", Mehungry.ObanWorkers.PubTatorAnnotationWorker},
    {"candidate_derivation_runs", Mehungry.ObanWorkers.CompoundCandidateDerivationWorker},
    {"recommendation_derivation_runs",
     Mehungry.ObanWorkers.RecommendationCandidateDerivationWorker}
  ]

  @live_states ~w(available scheduled executing retryable)

  # Only touch a run that has been quiet for this long, so we never race a job that
  # just finished a batch and is about to enqueue its successor.
  @default_grace_seconds 600

  @doc """
  Re-enqueue a batch for every stalled run across all stages. Returns the number
  of runs resumed. Options: `:grace_seconds` (default #{@default_grace_seconds}),
  `:stages` (defaults to all four — the test seam).
  """
  @spec resume_stalled(keyword()) :: non_neg_integer()
  def resume_stalled(opts \\ []) do
    grace = Keyword.get(opts, :grace_seconds, @default_grace_seconds)
    stages = Keyword.get(opts, :stages, @stages)
    cutoff = NaiveDateTime.utc_now() |> NaiveDateTime.add(-grace, :second)

    Enum.reduce(stages, 0, fn {table, worker}, acc ->
      acc + resume_stage(table, worker, cutoff)
    end)
  end

  defp resume_stage(table, worker, cutoff) do
    live = live_run_ids(worker)

    orphaned =
      Repo.query!(
        "SELECT id FROM #{table} WHERE status IN ('pending','processing') AND updated_at < $1",
        [cutoff]
      ).rows
      |> List.flatten()
      |> Enum.reject(&(&1 in live))

    Enum.each(orphaned, &resume(worker, table, &1))
    length(orphaned)
  end

  defp resume(worker, table, run_id) do
    Logger.warning(
      "[PipelineWatchdog] #{table} run #{run_id} stalled with no live Oban job — re-enqueuing a batch"
    )

    {:ok, _job} = %{"run_id" => run_id} |> worker.new() |> Oban.insert()
  end

  # run_ids referenced by any not-yet-finished job for this stage worker.
  defp live_run_ids(worker) do
    Repo.query!(
      "SELECT (args->>'run_id')::bigint FROM oban_jobs WHERE worker = $1 AND state = ANY($2)",
      [worker_name(worker), @live_states]
    ).rows
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
  end

  # Oban stores the worker without the "Elixir." module prefix.
  defp worker_name(worker), do: worker |> Atom.to_string() |> String.replace_prefix("Elixir.", "")
end
