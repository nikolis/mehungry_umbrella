defmodule Mehungry.ObanWorkers.LiteratureCrawlWorker do
  @moduledoc """
  Crawls NCBI Entrez (PubMed) for literature linking food species to compounds,
  one batch per run tick.

  A single job threads a `run_id` through a self-re-enqueueing chain, refreshing
  the run's progress each batch until every named food species has been crawled,
  then marking the run `completed`.

  Termination is guaranteed by the crawl ledger — `crawl_species/1` records an
  attempt for every `(species, term)` pair it touches, and the next batch excludes
  any species already attempted.

  Retries/rate limits (Oban `max_attempts: 3`):

    * a transient `{:error, {:rate_limited, retry_after}}` from a species crawl
      short-circuits the batch into an Oban `{:snooze, seconds}` so the still-
      uncrawled species are retried later rather than skipped;
    * any other transient `{:error, reason}` marks the run `failed` and returns
      `{:error, reason}` for Oban backoff **on all but the final attempt**.

  Both are idempotent because already-attempted `(species, term)` pairs are
  skipped on the retry.

  ## Poison-pill guard

  Mirrors `PubTatorAnnotationWorker`: a species whose first uncrawled term
  *persistently* errors (an NCBI network failure that never clears) bubbles
  `{:error, reason}` and is never ledgered — so it's re-selected on every retry and
  wedges the whole chain (batch halts → job exhausts its 3 attempts → `discarded` →
  no successor enqueued → the run strands in `processing`). On the **final** Oban
  attempt we stop bubbling and instead ledger the culprit species (a sentinel
  attempt row) so `list_uncrawled_species/1` stops selecting it, then enqueue the
  next batch so the chain steps past the pill. Genuine blips keep their full retry
  budget first.

  A chain that broke leaving nothing enqueued at all is resumed out-of-band by
  `Mehungry.Science.PipelineWatchdog`.
  """

  use Oban.Worker, queue: :imports, max_attempts: 3

  require Logger

  alias Mehungry.Literature
  alias Mehungry.Literature.CrawlRuns

  # Each species is several Entrez round-trips (one esearch + one efetch per
  # search term), so the batch is small to keep each pass inside NCBI rate limits.
  @batch_size 10

  # Rate-management defaults (overridable via app env — see config/config.exs):
  #   :entrez_pace_ms            delay between successive ingredient crawls
  #   :entrez_max_snooze_seconds upper bound applied to a rate-limit Retry-After
  @pace_ms Application.compile_env(:mehungry, :entrez_pace_ms, 300)
  @max_snooze_seconds Application.compile_env(:mehungry, :entrez_max_snooze_seconds, 3600)

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, attempt: attempt, max_attempts: max_attempts}) do
    run_id = Map.get(args, "run_id")
    CrawlRuns.mark_processing(run_id)

    case Literature.list_uncrawled_species(@batch_size) do
      [] ->
        Logger.info("LiteratureCrawlWorker: all named food species crawled")
        CrawlRuns.mark_completed(run_id, Literature.crawl_progress())
        :ok

      batch ->
        process_batch(batch, run_id, final_attempt?(attempt, max_attempts))
    end
  end

  defp process_batch(batch, run_id, final_attempt?) do
    case crawl_all(batch) do
      :ok ->
        advance(run_id)

      {:snooze, seconds} ->
        Logger.warning(
          "LiteratureCrawlWorker: rate-limited, snoozing #{seconds}s (retry uncrawled species)"
        )

        {:snooze, seconds}

      # Final attempt on a persistently-failing species: ledger it as skipped so the
      # chain can step past the poison pill, then keep going. See the moduledoc.
      {:error, species_id, reason} when final_attempt? ->
        Logger.error(
          "LiteratureCrawlWorker: species #{species_id} failed every attempt (#{inspect(reason)}) — " <>
            "marking it errored and skipping so the run can continue"
        )

        skip_poison_species(species_id)
        advance(run_id)

      {:error, _species_id, reason} ->
        Logger.warning(
          "LiteratureCrawlWorker: transient failure, will retry — #{inspect(reason)}"
        )

        CrawlRuns.mark_failed(run_id, reason)
        {:error, reason}
    end
  end

  # Refresh the coverage snapshot and hand the baton to the next batch.
  defp advance(run_id) do
    CrawlRuns.update_progress(run_id, Literature.crawl_progress())
    enqueue_next_batch(run_id)
    :ok
  end

  # Crawl each species in order. A rate-limit short-circuits into a snooze (the
  # already-crawled rows are ledgered); any other transient error halts for an
  # Oban retry with backoff, naming the species that failed so the worker can skip
  # it once its retry budget is spent.
  defp crawl_all(batch) do
    batch
    |> Enum.reduce_while({:ok, 0}, fn species, {:ok, idx} ->
      pace(idx)

      case Literature.import_species(species.id) do
        {:ok, _studies_found} ->
          {:cont, {:ok, idx + 1}}

        {:error, {:rate_limited, retry_after}} ->
          {:halt, {:snooze, clamp_snooze(retry_after)}}

        {:error, reason} ->
          {:halt, {:error, species.id, reason}}
      end
    end)
    |> case do
      {:ok, _count} -> :ok
      other -> other
    end
  end

  # Ledger a sentinel attempt so `list_uncrawled_species/1` stops re-selecting the
  # species (its selection guard is "has no attempt row at all").
  defp skip_poison_species(species_id) do
    Literature.record_crawl_attempt(%{
      foundemental_species_id: species_id,
      search_term: "(skipped after repeated crawl failure)",
      outcome: "error",
      studies_found: 0,
      last_crawled_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
  end

  defp final_attempt?(attempt, max_attempts), do: attempt >= max_attempts

  # Space out ingredient crawls under the shared rate budget; never before the first.
  defp pace(0), do: :ok
  defp pace(_idx), do: Process.sleep(@pace_ms)

  # Never snooze less than a second, never longer than the configured ceiling.
  defp clamp_snooze(retry_after) when is_integer(retry_after) do
    retry_after |> max(1) |> min(@max_snooze_seconds)
  end

  defp clamp_snooze(_), do: @max_snooze_seconds

  defp enqueue_next_batch(run_id) do
    %{"run_id" => run_id} |> new() |> Oban.insert!()
  end
end
