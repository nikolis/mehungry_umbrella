defmodule Mehungry.Science.PipelineWatchdogTest do
  use Mehungry.DataCase, async: false
  use Oban.Testing, repo: Mehungry.Repo

  alias Mehungry.{Literature, Repo}
  alias Mehungry.Literature.{AnnotationRun, AnnotationRuns, CrawlRun, CrawlRuns}
  alias Mehungry.Science.PipelineWatchdog
  alias Mehungry.ObanWorkers.{LiteratureCrawlWorker, PubTatorAnnotationWorker}

  # Backdate a run's `updated_at` so it counts as stalled under the default grace.
  defp stall(schema, id) do
    past = NaiveDateTime.utc_now() |> NaiveDateTime.add(-3600, :second)
    Repo.update_all(from(r in schema, where: r.id == ^id), set: [updated_at: past])
  end

  test "resumes a stalled annotation run with no live job by re-enqueuing a batch" do
    {:ok, _study} = Literature.upsert_study(%{pmid: 11_111, title: "s"})
    run = AnnotationRuns.start_run()
    stall(AnnotationRun, run.id)

    assert 1 = PipelineWatchdog.resume_stalled()
    assert_enqueued(worker: PubTatorAnnotationWorker, args: %{"run_id" => run.id})
  end

  test "resumes a stalled crawl run with no live job by re-enqueuing a batch" do
    run = CrawlRuns.start_run()
    stall(CrawlRun, run.id)

    assert 1 = PipelineWatchdog.resume_stalled()
    assert_enqueued(worker: LiteratureCrawlWorker, args: %{"run_id" => run.id})
  end

  test "resumes stalled runs across multiple stages in one sweep" do
    crawl = CrawlRuns.start_run()
    annotation = AnnotationRuns.start_run()
    stall(CrawlRun, crawl.id)
    stall(AnnotationRun, annotation.id)

    assert 2 = PipelineWatchdog.resume_stalled()
    assert_enqueued(worker: LiteratureCrawlWorker, args: %{"run_id" => crawl.id})
    assert_enqueued(worker: PubTatorAnnotationWorker, args: %{"run_id" => annotation.id})
  end

  test "leaves a stalled run alone while it still has a live Oban job" do
    run = AnnotationRuns.start_run()
    stall(AnnotationRun, run.id)

    # A queued (available) batch counts as live — the chain is not actually broken.
    {:ok, _job} = %{"run_id" => run.id} |> PubTatorAnnotationWorker.new() |> Oban.insert()

    # Only the pre-existing job — no second one enqueued by the watchdog.
    assert 0 = PipelineWatchdog.resume_stalled()
    assert 1 = Repo.aggregate(from(j in Oban.Job, where: j.worker == ^"Mehungry.ObanWorkers.PubTatorAnnotationWorker"), :count)
  end

  test "leaves a run that is still making progress (not yet stale) alone" do
    _run = AnnotationRuns.start_run()

    assert 0 = PipelineWatchdog.resume_stalled()
    refute_enqueued(worker: PubTatorAnnotationWorker)
  end

  test "ignores terminal (completed/failed) runs" do
    run = CrawlRuns.start_run()
    CrawlRuns.mark_completed(run.id, %{processed: 0, total: 0})
    stall(CrawlRun, run.id)

    assert 0 = PipelineWatchdog.resume_stalled()
    refute_enqueued(worker: LiteratureCrawlWorker)
  end
end
