defmodule Mehungry.ObanWorkers.PubTatorAnnotationWorkerTest do
  use Mehungry.DataCase, async: false
  use Oban.Testing, repo: Mehungry.Repo

  alias Mehungry.{Literature, Repo}
  alias Mehungry.Literature.AnnotationRuns
  alias Mehungry.Literature.{AnnotationAttempt, AnnotationRun, StudyEntityMention}
  alias Mehungry.ObanWorkers.PubTatorAnnotationWorker, as: Worker

  defp stub_ok do
    Application.put_env(:mehungry, :pubtator_http_adapter, fn _url, _h, _o ->
      {:ok, %{status_code: 200, body: biocjson(), headers: []}}
    end)

    # The chemical resolves via PubChem; stub it so no test reaches the network.
    Application.put_env(:mehungry, :pubchem_http_adapter, fn url, _h, _o ->
      body =
        cond do
          String.contains?(url, "/cids") ->
            %{"IdentifierList" => %{"CID" => [971]}}

          String.contains?(url, "/property/") ->
            %{"PropertyTable" => %{"Properties" => [%{"CID" => 971, "Title" => "Oxalic acid"}]}}

          String.contains?(url, "/synonyms") ->
            %{"InformationList" => %{"Information" => [%{"CID" => 971, "Synonym" => []}]}}
        end

      {:ok, %{status_code: 200, body: Jason.encode!(body), headers: []}}
    end)

    Cachex.clear(:pubtator_cache)
    Cachex.clear(:pubchem_cache)

    on_exit(fn ->
      Application.delete_env(:mehungry, :pubtator_http_adapter)
      Application.delete_env(:mehungry, :pubchem_http_adapter)
    end)
  end

  defp stub_rate_limited do
    Application.put_env(:mehungry, :pubtator_http_adapter, fn _url, _h, _o ->
      {:ok, %{status_code: 429, body: "", headers: [{"Retry-After", "30"}]}}
    end)

    Cachex.clear(:pubtator_cache)
    on_exit(fn -> Application.delete_env(:mehungry, :pubtator_http_adapter) end)
  end

  # A study PubTator persistently fails to annotate with a (non rate-limit)
  # transient network error — the poison-pill case.
  defp stub_network_error do
    Application.put_env(:mehungry, :pubtator_http_adapter, fn _url, _h, _o ->
      {:error, %HTTPoison.Error{reason: :timeout}}
    end)

    Cachex.clear(:pubtator_cache)
    on_exit(fn -> Application.delete_env(:mehungry, :pubtator_http_adapter) end)
  end

  defp biocjson do
    Jason.encode!(%{
      "documents" => [
        %{
          "id" => "11111",
          "passages" => [
            %{
              "offset" => 0,
              "text" => "Oxalate in spinach.",
              "annotations" => [
                %{
                  "infons" => %{"type" => "Chemical", "identifier" => "MESH:D010070"},
                  "text" => "Oxalate",
                  "locations" => [%{"offset" => 0, "length" => 7}]
                }
              ]
            }
          ]
        }
      ]
    })
  end

  defp study_fixture(pmid) do
    {:ok, study} = Literature.upsert_study(%{pmid: pmid, title: "study #{pmid}"})
    study
  end

  test "annotates a batch, records mentions + attempts, tracks progress, chains next batch" do
    stub_ok()
    study = study_fixture(11_111)
    run = AnnotationRuns.start_run()

    assert :ok = perform_job(Worker, %{"run_id" => run.id})

    assert Repo.aggregate(StudyEntityMention, :count) == 1

    assert Repo.aggregate(from(a in AnnotationAttempt, where: a.study_id == ^study.id), :count) ==
             1

    reloaded = Repo.get!(AnnotationRun, run.id)
    assert reloaded.status == "processing"
    assert reloaded.processed >= 1
    assert_enqueued(worker: Worker)
  end

  test "completes the run and stops chaining when nothing is left to annotate" do
    stub_ok()
    # No discovered studies → nothing to annotate.
    run = AnnotationRuns.start_run()

    assert :ok = perform_job(Worker, %{"run_id" => run.id})

    assert Repo.get!(AnnotationRun, run.id).status == "completed"
    refute_enqueued(worker: Worker)
  end

  test "a rate limit snoozes the job and leaves the run un-failed for retry" do
    stub_rate_limited()
    _study = study_fixture(11_111)
    run = AnnotationRuns.start_run()

    assert {:snooze, 30} = perform_job(Worker, %{"run_id" => run.id})

    refute Repo.get!(AnnotationRun, run.id).status == "failed"
  end

  test "a persistently-failing study fails the batch for a retry on a non-final attempt" do
    stub_network_error()
    study = study_fixture(11_111)
    run = AnnotationRuns.start_run()

    assert {:error, _reason} = perform_job(Worker, %{"run_id" => run.id}, attempt: 1)

    # Not ledgered — a genuine blip must keep its full retry budget.
    refute Repo.exists?(from(a in AnnotationAttempt, where: a.study_id == ^study.id))
    assert Repo.get!(AnnotationRun, run.id).status == "failed"
  end

  test "on the final attempt a poison-pill study is skipped so the chain continues" do
    stub_network_error()
    study = study_fixture(11_111)
    run = AnnotationRuns.start_run()

    assert :ok = perform_job(Worker, %{"run_id" => run.id}, attempt: 3, max_attempts: 3)

    # The culprit is ledgered as an error so it is never re-selected...
    attempt = Repo.get_by!(AnnotationAttempt, study_id: study.id)
    assert attempt.outcome == "error"

    # ...the chain keeps going (next batch enqueued) and the run stays alive.
    assert_enqueued(worker: Worker)
    refute Repo.get!(AnnotationRun, run.id).status == "failed"
  end
end
