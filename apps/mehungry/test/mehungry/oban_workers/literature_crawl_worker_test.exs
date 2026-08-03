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

  # A species Entrez persistently fails to crawl with a (non rate-limit) transient
  # network error on its first term — the poison-pill case.
  defp stub_network_error do
    Application.put_env(:mehungry, :entrez_http_adapter, fn _url, _headers, _opts ->
      {:error, %HTTPoison.Error{reason: :timeout}}
    end)

    Cachex.clear(:entrez_cache)
    on_exit(fn -> Application.delete_env(:mehungry, :entrez_http_adapter) end)
  end

  defp efetch_xml do
    """
    <?xml version="1.0"?>
    <!DOCTYPE PubmedArticleSet PUBLIC "-//NLM//DTD PubMedArticle, 1st January 2019//EN" "https://dtd.nlm.nih.gov/ncbi/pubmed/out/pubmed_190101.dtd">
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

  defp spinach_species(name \\ "spinach") do
    ingredient = ingredient_fixture(%{name: name})

    {:ok, species} =
      Food.create_foundemental_species(%{
        "name" => "Spinach",
        "scientific_name" => "Spinacia oleracea"
      })

    {:ok, _} = Food.assign_foundemental_ingredient(species.id, ingredient.id, name)

    %{ingredient: ingredient, species: species}
  end

  test "crawls a batch, records studies + attempts, tracks progress, chains next batch" do
    stub_ok()
    %{species: species} = spinach_species()
    run = CrawlRuns.start_run()

    assert :ok = perform_job(Worker, %{"run_id" => run.id})

    assert Repo.aggregate(from(s in ScientificStudy, where: s.pmid == 11111), :count) == 1

    assert Repo.aggregate(
             from(a in CrawlAttempt, where: a.foundemental_species_id == ^species.id),
             :count
           ) >= 1

    reloaded = Repo.get!(CrawlRun, run.id)
    assert reloaded.status == "processing"
    assert reloaded.processed >= 1
    assert_enqueued(worker: Worker)
  end

  test "completes the run and stops chaining when nothing is left to crawl" do
    stub_ok()
    # No species has a scientific name → nothing to crawl.
    run = CrawlRuns.start_run()

    assert :ok = perform_job(Worker, %{"run_id" => run.id})

    assert Repo.get!(CrawlRun, run.id).status == "completed"
    refute_enqueued(worker: Worker)
  end

  test "a rate limit snoozes the job and leaves the run un-failed for retry" do
    stub_rate_limited()
    _spinach = spinach_species()
    run = CrawlRuns.start_run()

    assert {:snooze, 30} = perform_job(Worker, %{"run_id" => run.id})

    # Snooze (not fail) so the uncrawled species is retried later.
    refute Repo.get!(CrawlRun, run.id).status == "failed"
  end

  test "a persistently-failing species fails the batch for a retry on a non-final attempt" do
    stub_network_error()
    %{species: species} = spinach_species()
    run = CrawlRuns.start_run()

    assert {:error, _reason} = perform_job(Worker, %{"run_id" => run.id}, attempt: 1)

    # Not ledgered — a genuine blip must keep its full retry budget.
    refute Repo.exists?(
             from(a in CrawlAttempt, where: a.foundemental_species_id == ^species.id)
           )

    assert Repo.get!(CrawlRun, run.id).status == "failed"
  end

  test "on the final attempt a poison-pill species is skipped so the chain continues" do
    stub_network_error()
    %{species: species} = spinach_species()
    run = CrawlRuns.start_run()

    assert :ok = perform_job(Worker, %{"run_id" => run.id}, attempt: 3, max_attempts: 3)

    # The culprit is ledgered so it is never re-selected...
    attempt = Repo.get_by!(CrawlAttempt, foundemental_species_id: species.id)
    assert attempt.outcome == "error"

    # ...the chain keeps going (next batch enqueued) and the run stays alive.
    assert_enqueued(worker: Worker)
    refute Repo.get!(CrawlRun, run.id).status == "failed"
  end
end
