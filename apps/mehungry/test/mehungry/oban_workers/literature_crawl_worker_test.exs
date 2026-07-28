defmodule Mehungry.ObanWorkers.LiteratureCrawlWorkerTest do
  use Mehungry.DataCase, async: false
  use Oban.Testing, repo: Mehungry.Repo

  import Mehungry.FoodFixtures

  alias Mehungry.{Food, Repo}
  alias Mehungry.Literature.CrawlRuns
  alias Mehungry.Literature.{CrawlAttempt, ScientificStudy, CrawlRun}
  alias Mehungry.ObanWorkers.LiteratureCrawlWorker, as: Worker

  defp stub_ok do
    Application.put_env(:mehungry, :entrez_http_adapter, fn url, _headers, _opts ->
      cond do
        String.contains?(url, "esearch.fcgi") ->
          {:ok,
           %{
             status_code: 200,
             body: Jason.encode!(%{"esearchresult" => %{"count" => "1", "idlist" => ["11111"]}}),
             headers: []
           }}

        String.contains?(url, "efetch.fcgi") ->
          {:ok, %{status_code: 200, body: efetch_xml(), headers: []}}
      end
    end)

    Cachex.clear(:entrez_cache)
    on_exit(fn -> Application.delete_env(:mehungry, :entrez_http_adapter) end)
  end

  defp stub_rate_limited do
    Application.put_env(:mehungry, :entrez_http_adapter, fn _url, _headers, _opts ->
      {:ok, %{status_code: 429, body: "", headers: [{"Retry-After", "30"}]}}
    end)

    Cachex.clear(:entrez_cache)
    on_exit(fn -> Application.delete_env(:mehungry, :entrez_http_adapter) end)
  end

  defp efetch_xml do
    """
    <?xml version="1.0"?>
    <PubmedArticleSet>
      <PubmedArticle>
        <MedlineCitation>
          <PMID Version="1">11111</PMID>
          <Article>
            <Journal><Title>J Food Sci</Title></Journal>
            <ArticleTitle>Oxalate in spinach</ArticleTitle>
          </Article>
        </MedlineCitation>
      </PubmedArticle>
    </PubmedArticleSet>
    """
  end

  defp spinach_with_identity(name \\ "spinach") do
    ingredient = ingredient_fixture(%{name: name})

    {:ok, _identity, _} =
      Food.add_identity_candidate(%{
        ingredient_id: ingredient.id,
        scientific_name: "Spinacia oleracea",
        source: "usda_fdc",
        confidence: 0.9,
        status: "candidate"
      })

    ingredient
  end

  test "crawls a batch, records studies + attempts, tracks progress, chains next batch" do
    stub_ok()
    ingredient = spinach_with_identity()
    run = CrawlRuns.start_run()

    assert :ok = perform_job(Worker, %{"run_id" => run.id})

    assert Repo.aggregate(from(s in ScientificStudy, where: s.pmid == 11111), :count) == 1

    assert Repo.aggregate(
             from(a in CrawlAttempt, where: a.ingredient_id == ^ingredient.id),
             :count
           ) >= 1

    reloaded = Repo.get!(CrawlRun, run.id)
    assert reloaded.status == "processing"
    assert reloaded.processed >= 1
    assert_enqueued(worker: Worker)
  end

  test "completes the run and stops chaining when nothing is left to crawl" do
    stub_ok()
    # No ingredient has a scientific identity → nothing to crawl.
    run = CrawlRuns.start_run()

    assert :ok = perform_job(Worker, %{"run_id" => run.id})

    assert Repo.get!(CrawlRun, run.id).status == "completed"
    refute_enqueued(worker: Worker)
  end

  test "a rate limit snoozes the job and leaves the run un-failed for retry" do
    stub_rate_limited()
    _ingredient = spinach_with_identity()
    run = CrawlRuns.start_run()

    assert {:snooze, 30} = perform_job(Worker, %{"run_id" => run.id})

    # Snooze (not fail) so the uncrawled ingredient is retried later.
    refute Repo.get!(CrawlRun, run.id).status == "failed"
  end
end
