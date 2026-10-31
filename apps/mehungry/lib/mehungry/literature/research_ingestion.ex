defmodule Mehungry.Literature.ResearchIngestion do
  @moduledoc """
  The shared ingest core for the nutritionist research search — the one place that
  sends a condition's crawled studies to the `mehungry_extractor` `POST /analyze`
  and persists the result. Reused by **both** entry points so the logic lives once:

    * `mix research.ingest` — the offline, command-line one-shot runner;
    * `Mehungry.ObanWorkers.ResearchIngestionWorker` — the admin-triggered,
      UI-controlled background run (`/professional/health`).

  `analyze_condition/2` is the unit: it optionally crawls PubMed first, selects the
  condition's studies that still need analyzing (skipping already-analyzed unless
  `force`, and always skipping `unusable`/non-open-access ones), then sends them to
  the extractor in `≤ batch`-PMID chunks and stores each response via
  `Mehungry.Literature.store_analysis_response/1` (claims **and** the full-text
  `sections` outline). The extractor is the only online dependency, and only here —
  once stored, the search reads purely from the DB.
  """

  require Logger

  alias Mehungry.Literature

  @extractor_max 200

  @typedoc "Per-condition store totals, summed across the condition's batches."
  @type counts :: %{inserted: non_neg_integer, updated: non_neg_integer, unchanged: non_neg_integer, skipped: non_neg_integer}

  @doc "Empty counts accumulator."
  @spec zero_counts() :: counts()
  def zero_counts, do: %{inserted: 0, updated: 0, unchanged: 0, skipped: 0}

  @doc "Sum two count maps."
  @spec merge_counts(counts(), counts()) :: counts()
  def merge_counts(a, b), do: Map.merge(a, b, fn _k, v1, v2 -> v1 + v2 end)

  @doc """
  Analyze one condition. `opts`:

    * `:crawl`  — PubMed-crawl the condition first (NCBI, not the extractor).
    * `:force`  — re-analyze even already-analyzed studies (backfills `sections`).
    * `:batch`  — extractor batch size (default/`max` 200).

  Returns `{:ok, counts, target_count}` (store totals + how many studies were sent),
  or `{:error, reason}` if an extractor call fails (so the caller can abort and
  keep already-stored work). A condition with nothing to analyze returns
  `{:ok, zero_counts(), 0}` without touching the extractor.
  """
  @spec analyze_condition(integer(), keyword()) ::
          {:ok, counts(), non_neg_integer()} | {:error, term()}
  def analyze_condition(condition_id, opts \\ []) do
    if opts[:crawl], do: Literature.crawl_condition(condition_id)

    batch = min(opts[:batch] || @extractor_max, @extractor_max)
    pmids = target_pmids(condition_id, opts[:force] || false)

    pmids
    |> Enum.chunk_every(batch)
    |> reduce_batches(length(pmids))
  end

  @doc """
  The PMIDs (as strings) this condition still needs analyzed.

  - **Normal** (`force: false`): studies not yet analyzed, minus the `unusable`
    ones (non-open-access, including unknown source) — i.e. new work only.
  - **Force** (`force: true`): re-analyze everything **except** papers *known* to
    be abstract-only/`none` (re-analyzing those can't produce full text). Crucially
    this **re-includes `nil`/unknown-source papers** — those analyzed by an older
    extractor that didn't record `source_type` — so a force run can discover they
    are open-access and backfill their `sections` outline.
  """
  @spec target_pmids(integer(), boolean()) :: [String.t()]
  def target_pmids(condition_id, force \\ false) do
    studies =
      condition_id
      |> Literature.list_studies_for_condition()
      |> Enum.filter(& &1.pmid)

    ids = Enum.map(studies, & &1.id)

    skip =
      if force do
        # Only skip papers we *know* have no full text; retry unknowns + open-access.
        Literature.known_abstract_study_ids(ids)
      else
        # New work only: skip anything already analyzed or flagged unusable.
        MapSet.union(Literature.analyzed_study_ids(ids), Literature.unusable_study_ids(ids))
      end

    studies
    |> Enum.reject(&MapSet.member?(skip, &1.id))
    |> Enum.map(&to_string(&1.pmid))
  end

  defp reduce_batches(batches, target_count) do
    Enum.reduce_while(batches, {:ok, zero_counts(), target_count}, fn pmids, {:ok, acc, n} ->
      case analyze_batch(pmids) do
        {:ok, counts} -> {:cont, {:ok, merge_counts(acc, counts), n}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp analyze_batch(pmids) do
    case Mehungry.Extractor.client().analyze(pmids, []) do
      {:ok, response} ->
        {:ok, counts} = Literature.store_analysis_response(response)
        {:ok, counts}

      {:error, reason} ->
        Logger.warning("[ResearchIngestion] extractor /analyze failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
