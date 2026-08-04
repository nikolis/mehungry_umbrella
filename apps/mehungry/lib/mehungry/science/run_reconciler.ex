defmodule Mehungry.Science.RunReconciler do
  @moduledoc """
  Boot-time reconciler for the scientific-pipeline run records.

  A crawl/annotation/derivation run row transitions `pending → processing →
  completed|failed`, but if `phx.server` is stopped mid-run the row is left stuck
  in `processing` with no Oban job to finish it — which permanently disables that
  stage's Run button in `/professional/science` (its `running?/1` guard stays true).

  On every boot we mark any `pending`/`processing` run that has **no live Oban job**
  (a job in `available`/`scheduled`/`retryable`, or a *fresh* `executing` one, whose
  `args.run_id` points at it) as `failed`, so a restart never leaves the UI blocked.
  A run with a genuinely in-flight job is left alone.

  ## Zombie `executing` jobs

  A crash / OOM / `kill -9` mid-batch leaves the job row wedged in `executing` with
  no process behind it; Oban's `Lifeline` only reaps it back to `available` after
  its (24h) `rescue_after` window. If we counted that zombie as a live job, the
  reconciler would leave the run stuck in `processing` — the Run button disabled —
  for up to a day after the very restart it is meant to heal. So an `executing` job
  whose `attempted_at` predates `@executing_grace_seconds` is treated as **not**
  live: no real pipeline batch runs that long, and at boot nothing this node
  started is executing yet, so a stale `executing` row is always a previous-life
  orphan. The run is then marked `failed` like any other orphan, re-enabling its
  Run button.

  Gated by `config :mehungry, :reconcile_runs_on_boot` (default `true`; off in test
  so it never races the Ecto sandbox).
  """

  require Logger

  alias Mehungry.Repo
  alias Mehungry.Literature.{AnnotationRuns, CrawlRuns}
  alias Mehungry.Food.CandidateDerivationRuns
  alias Mehungry.Health.RecommendationDerivationRuns

  # {run table, Oban worker (as stored — no "Elixir." prefix), run module with mark_failed/2}
  @stages [
    {"literature_crawl_runs", "Mehungry.ObanWorkers.LiteratureCrawlWorker", CrawlRuns},
    {"pubtator_annotation_runs", "Mehungry.ObanWorkers.PubTatorAnnotationWorker", AnnotationRuns},
    {"candidate_derivation_runs", "Mehungry.ObanWorkers.CompoundCandidateDerivationWorker",
     CandidateDerivationRuns},
    {"recommendation_derivation_runs",
     "Mehungry.ObanWorkers.RecommendationCandidateDerivationWorker",
     RecommendationDerivationRuns}
  ]

  # `executing` is handled separately (see `live_run_ids/1`): a fresh one is live, a
  # stale one is a crash-orphaned zombie and must not keep a wedged run alive.
  @live_states ~w(available scheduled retryable)

  # An `executing` job older than this is a previous-life orphan, not live work.
  @executing_grace_seconds 300

  @doc "Runs `reconcile/0` unless disabled by config; never crashes boot."
  def reconcile_on_boot do
    if Application.get_env(:mehungry, :reconcile_runs_on_boot, true) do
      try do
        reconcile()
      rescue
        e -> Logger.warning("[RunReconciler] skipped: #{Exception.message(e)}")
      end
    end
  end

  @doc "Marks orphaned in-flight runs failed across all stages. Returns total count."
  def reconcile do
    Enum.reduce(@stages, 0, fn {table, worker, run_mod}, acc ->
      acc + reconcile_stage(table, worker, run_mod)
    end)
  end

  defp reconcile_stage(table, worker, run_mod) do
    live = live_run_ids(worker)

    stuck =
      Repo.query!("SELECT id FROM #{table} WHERE status IN ('pending','processing')").rows
      |> List.flatten()

    orphaned = Enum.reject(stuck, &(&1 in live))

    Enum.each(orphaned, fn id ->
      Logger.warning("[RunReconciler] #{table} run #{id} orphaned (no live Oban job) — marking failed")
      run_mod.mark_failed(id, "orphaned at boot — no live Oban job (server stopped mid-run)")
    end)

    length(orphaned)
  end

  # run_ids referenced by any not-yet-finished Oban job for this worker. A queued
  # (`available`/`scheduled`/`retryable`) job is always live; an `executing` job is
  # live only if it started within the grace window — a stale one is a
  # crash-orphaned zombie (see the moduledoc) that must not keep a run wedged.
  defp live_run_ids(worker) do
    cutoff = DateTime.utc_now() |> DateTime.add(-@executing_grace_seconds, :second)

    Repo.query!(
      """
      SELECT (args->>'run_id')::bigint
      FROM oban_jobs
      WHERE worker = $1
        AND (state = ANY($2) OR (state = 'executing' AND attempted_at >= $3))
      """,
      [worker, @live_states, cutoff]
    ).rows
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
  end
end
