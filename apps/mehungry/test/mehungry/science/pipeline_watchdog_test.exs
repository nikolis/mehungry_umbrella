defmodule Mehungry.Science.PipelineWatchdogTest do
  use Mehungry.DataCase, async: false
  use Oban.Testing, repo: Mehungry.Repo

  alias Mehungry.Repo
  alias Mehungry.Literature.{ConditionCrawlRun, ConditionCrawlRuns}
  alias Mehungry.Science.PipelineWatchdog
  alias Mehungry.ObanWorkers.ConditionCrawlWorker

  # Phase 1 of the research-search reshape trimmed the watchdog to the one stage
  # that still runs: the condition-seeded crawl (the research-search acquisition
  # path). The generation stages (species crawl, PubTator annotation, compound-
  # & recommendation-candidate derivation) are decommissioned and no longer
  # watched. The watchdog's stalled/live/zombie/terminal logic is unchanged and
  # is exercised here against condition crawl.

  # Backdate a run's `updated_at` so it counts as stalled under the default grace.
  defp stall(schema, id) do
    past = NaiveDateTime.utc_now() |> NaiveDateTime.add(-3600, :second)
    Repo.update_all(from(r in schema, where: r.id == ^id), set: [updated_at: past])
  end

  # Force an inserted Oban job into `executing` with a chosen `attempted_at`, to
  # simulate a live batch (fresh) vs. a crash-orphaned zombie (stale).
  defp set_executing(%Oban.Job{id: id}, attempted_at) do
    Repo.update_all(
      from(j in Oban.Job, where: j.id == ^id),
      set: [state: "executing", attempted_at: attempted_at]
    )
  end

  test "resumes a stalled condition-crawl run with no live job by re-enqueuing a batch" do
    run = ConditionCrawlRuns.start_run()
    stall(ConditionCrawlRun, run.id)

    assert 1 = PipelineWatchdog.resume_stalled()
    assert_enqueued(worker: ConditionCrawlWorker, args: %{"run_id" => run.id})
  end

  test "leaves a stalled run alone while it still has a live Oban job" do
    run = ConditionCrawlRuns.start_run()
    stall(ConditionCrawlRun, run.id)

    # A queued (available) batch counts as live — the chain is not actually broken.
    {:ok, _job} = %{"run_id" => run.id} |> ConditionCrawlWorker.new() |> Oban.insert()

    # Only the pre-existing job — no second one enqueued by the watchdog.
    assert 0 = PipelineWatchdog.resume_stalled()

    assert 1 =
             Repo.aggregate(
               from(j in Oban.Job,
                 where: j.worker == ^"Mehungry.ObanWorkers.ConditionCrawlWorker"
               ),
               :count
             )
  end

  test "leaves a run alone while a fresh (recently-started) executing job holds it" do
    run = ConditionCrawlRuns.start_run()
    stall(ConditionCrawlRun, run.id)

    {:ok, job} = %{"run_id" => run.id} |> ConditionCrawlWorker.new() |> Oban.insert()
    set_executing(job, NaiveDateTime.utc_now())

    assert 0 = PipelineWatchdog.resume_stalled()
    refute_enqueued(worker: ConditionCrawlWorker, args: %{"run_id" => run.id})
  end

  test "resumes a run whose only job is a stale (crash-orphaned) executing zombie" do
    run = ConditionCrawlRuns.start_run()
    stall(ConditionCrawlRun, run.id)

    # An `executing` row wedged by a hard crash, its attempted_at long past the grace
    # window — Lifeline won't reap it for 24h, but the watchdog must not wait.
    {:ok, job} = %{"run_id" => run.id} |> ConditionCrawlWorker.new() |> Oban.insert()
    set_executing(job, NaiveDateTime.utc_now() |> NaiveDateTime.add(-3600, :second))

    assert 1 = PipelineWatchdog.resume_stalled()
    assert_enqueued(worker: ConditionCrawlWorker, args: %{"run_id" => run.id})
  end

  test "leaves a run that is still making progress (not yet stale) alone" do
    _run = ConditionCrawlRuns.start_run()

    assert 0 = PipelineWatchdog.resume_stalled()
    refute_enqueued(worker: ConditionCrawlWorker)
  end

  test "ignores terminal (completed/failed) runs" do
    run = ConditionCrawlRuns.start_run()
    ConditionCrawlRuns.mark_completed(run.id, %{processed: 0, total: 0})
    stall(ConditionCrawlRun, run.id)

    assert 0 = PipelineWatchdog.resume_stalled()
    refute_enqueued(worker: ConditionCrawlWorker)
  end
end
