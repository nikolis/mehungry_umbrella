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
      `{:error, reason}` for Oban backoff.

  Both are idempotent because already-attempted `(species, term)` pairs are
  skipped on the retry.
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
  def perform(%Oban.Job{args: args}) do
    run_id = Map.get(args, "run_id")
    CrawlRuns.mark_processing(run_id)

    case Literature.list_uncrawled_species(@batch_size) do
      [] ->
        Logger.info("LiteratureCrawlWorker: all named food species crawled")
        CrawlRuns.mark_completed(run_id, Literature.crawl_progress())
        :ok

      batch ->
        process_batch(batch, run_id)
    end
  end

  defp process_batch(batch, run_id) do
    case crawl_all(batch) do
      :ok ->
        CrawlRuns.update_progress(run_id, Literature.crawl_progress())
        enqueue_next_batch(run_id)
        :ok

      {:snooze, seconds} ->
        Logger.warning(
          "LiteratureCrawlWorker: rate-limited, snoozing #{seconds}s (retry uncrawled species)"
        )

        {:snooze, seconds}

      {:error, reason} ->
        Logger.warning(
          "LiteratureCrawlWorker: transient failure, will retry — #{inspect(reason)}"
        )

        CrawlRuns.mark_failed(run_id, reason)
        {:error, reason}
    end
  end

  # Crawl each species in order. A rate-limit short-circuits into a snooze (the
  # already-crawled rows are ledgered); any other transient error halts for an
  # Oban retry with backoff.
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
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, _count} -> :ok
      other -> other
    end
  end

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
