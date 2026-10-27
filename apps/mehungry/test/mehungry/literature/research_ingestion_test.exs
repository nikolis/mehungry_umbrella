defmodule Mehungry.Literature.ResearchIngestionTest do
  @moduledoc """
  The admin-triggered bulk research ingestion: enqueue guard, the sequential
  worker, and run-row progress/lifecycle. The extractor is stubbed
  (`:extractor_client` → `ClientStub`, overridden per test via `:extractor_stub`).
  """
  use Mehungry.DataCase, async: false
  use Oban.Testing, repo: Mehungry.Repo

  alias Mehungry.{Health, Literature, Repo}
  alias Mehungry.Literature.StudyCondition
  alias Mehungry.Literature.ResearchIngestionRuns, as: Runs
  alias Mehungry.ObanWorkers.ResearchIngestionWorker

  # A stub `/analyze` response: one open-access paper per pmid, each with a
  # one-section full-text outline and a claim (so sections get stored).
  defp stub_with_sections do
    Application.put_env(:mehungry, :extractor_stub,
      analyze: fn pmids, _opts ->
        {:ok,
         %{
           "run" => %{"synthesis_version" => "0.1.0"},
           "papers" =>
             Enum.map(pmids, fn pmid ->
               %{
                 "pmid" => pmid,
                 "status" => "included",
                 "title" => "Paper #{pmid}",
                 "source_type" => "open_access",
                 "study_design" => "cohort"
               }
             end),
           "paper_claims" =>
             Enum.map(pmids, fn pmid ->
               %{
                 "pmid" => pmid,
                 "paper_title" => "Paper #{pmid}",
                 "sections" => [
                   %{
                     "section_id" => "sec-#{pmid}",
                     "index" => 0,
                     "title" => "Introduction",
                     "start_char" => 0,
                     "end_char" => 20,
                     "paragraphs" => [
                       %{
                         "paragraph_id" => "par-#{pmid}",
                         "start_char" => 0,
                         "end_char" => 20,
                         "text" => "Fiber aids remission"
                       }
                     ]
                   }
                 ],
                 "claims_list" => [
                   %{"claim_id" => "c-#{pmid}", "predicate" => "improves", "polarity" => "positive"}
                 ]
               }
             end)
         }}
      end
    )

    on_exit(fn -> Application.delete_env(:mehungry, :extractor_stub) end)
  end

  defp condition_with_study(name, pmid) do
    {:ok, condition} = Health.create_condition(%{name: name})
    {:ok, study} = Literature.upsert_study(%{pmid: pmid, title: "P#{pmid}"})

    Repo.insert!(
      StudyCondition.changeset(%StudyCondition{}, %{
        study_id: study.id,
        condition_id: condition.id,
        search_term: "diet"
      })
    )

    {condition, study}
  end

  defp job_args(run, condition_id) do
    %{
      "run_id" => run.id,
      "condition_id" => condition_id,
      "crawl" => false,
      "force" => false,
      "batch" => 200
    }
  end

  describe "enqueue/1" do
    test "opens a processing run and fans out one job per condition" do
      {c1, _} = condition_with_study("Ulcerative Colitis", 90_001)
      {c2, _} = condition_with_study("Crohn", 90_002)

      assert {:ok, run} = Runs.enqueue([])
      assert run.status == "processing"
      assert run.conditions_total == 2
      assert_enqueued(worker: ResearchIngestionWorker, args: %{"condition_id" => c1.id})
      assert_enqueued(worker: ResearchIngestionWorker, args: %{"condition_id" => c2.id})
    end

    test "refuses a second run while one is in flight" do
      condition_with_study("IBS", 90_003)

      assert {:ok, run} = Runs.enqueue([])
      assert {:error, :already_running, ^run} = Runs.enqueue([])
    end

    test "errors when no condition matches the filter" do
      assert {:error, :no_conditions} = Runs.enqueue(condition: "no-such-condition-xyz")
    end
  end

  describe "worker run" do
    setup do
      stub_with_sections()
      :ok
    end

    test "analyzes one condition, stores sections, and finalizes the run" do
      {condition, study} = condition_with_study("Crohn", 90_010)
      {:ok, run} = Runs.enqueue([])

      assert :ok = perform_job(ResearchIngestionWorker, job_args(run, condition.id))

      run = Runs.latest_run()
      # Single condition → that one job finalizes the run.
      assert run.status == "completed"
      assert run.conditions_done == 1
      assert run.inserted == 1
      assert is_nil(run.current_condition)

      # The full-text outline was persisted → the reader + card light up.
      assert %{sections: [%{"section_id" => "sec-90010"}]} =
               Literature.full_text_for_reader(study.id)
    end

    test "retries on a transient extractor error (not the last attempt)" do
      {condition, _} = condition_with_study("Gastritis", 90_020)
      {:ok, run} = Runs.enqueue([])

      Application.put_env(:mehungry, :extractor_stub,
        analyze: fn _pmids, _opts -> {:error, {:network, :econnrefused}} end
      )

      # attempt 1 of 3 → ask Oban to retry, run stays processing.
      assert {:error, {:network, :econnrefused}} =
               perform_job(ResearchIngestionWorker, job_args(run, condition.id), attempt: 1)

      assert Runs.latest_run().status == "processing"
    end

    test "on the final attempt records a condition failure and finalizes" do
      {condition, _} = condition_with_study("Colitis", 90_030)
      {:ok, run} = Runs.enqueue([])

      Application.put_env(:mehungry, :extractor_stub,
        analyze: fn _pmids, _opts -> {:error, {:network, :econnrefused}} end
      )

      # Last attempt → swallow + record the condition as failed; the run finalizes.
      assert :ok =
               perform_job(ResearchIngestionWorker, job_args(run, condition.id),
                 attempt: 3,
                 max_attempts: 3
               )

      run = Runs.latest_run()
      # Every condition (the only one) failed → the run goes red, not "completed".
      assert run.status == "failed"
      assert run.conditions_failed == 1
      assert run.error =~ "econnrefused"
    end

    test "a run with a mix of success + failure finalizes as completed" do
      {c1, _} = condition_with_study("Anemia", 90_031)
      {c2, _} = condition_with_study("Rickets", 90_032)
      {:ok, run} = Runs.enqueue([])

      # c1 succeeds (default stub).
      assert :ok = perform_job(ResearchIngestionWorker, job_args(run, c1.id))

      # c2 fails on its final attempt.
      Application.put_env(:mehungry, :extractor_stub,
        analyze: fn _pmids, _opts -> {:error, {:network, :econnrefused}} end
      )

      assert :ok =
               perform_job(ResearchIngestionWorker, job_args(run, c2.id),
                 attempt: 3,
                 max_attempts: 3
               )

      run = Runs.latest_run()
      # Not every condition failed → completed, with the failure still visible.
      assert run.status == "completed"
      assert run.conditions_done == 1
      assert run.conditions_failed == 1
    end
  end

  describe "recovery" do
    test "cancel_active cancels jobs and marks the run failed" do
      condition_with_study("IBD", 90_040)
      {:ok, _run} = Runs.enqueue([])

      run = Runs.cancel_active()
      assert run.status == "failed"
      assert run.error == "cancelled by admin"
      assert is_nil(Runs.active_run())
    end

    test "reconcile_stale fails a processing run with no live jobs" do
      # A run row left processing, but no Oban jobs back it (simulating a restart
      # that discarded them).
      run = Runs.start_run(3, %{})
      assert Runs.active_run().id == run.id

      reconciled = Runs.reconcile_stale()
      assert reconciled.status == "failed"
      assert reconciled.error =~ "stalled"
    end
  end
end
