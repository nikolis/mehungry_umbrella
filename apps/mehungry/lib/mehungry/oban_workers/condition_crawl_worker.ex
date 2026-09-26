defmodule Mehungry.ObanWorkers.ConditionCrawlWorker do
  @moduledoc """
  Reverse (condition-seeded) literature crawl — the condition analogue of
  `LiteratureCrawlWorker`. Crawls NCBI Entrez for studies *about* each
  phase-sensitive condition (one with `condition_states`), one batch per run tick,
  linking discovered papers to the condition via `study_conditions`.

  A single job threads a `run_id` through a self-re-enqueueing chain until every
  state-bearing condition has been crawled, then marks the run `completed`.
  Termination is guaranteed by the condition-crawl ledger.

  Retries/rate limits and the poison-pill guard mirror `LiteratureCrawlWorker`: a
  transient `{:rate_limited, _}` snoozes; a condition that fails every attempt is
  ledgered with a sentinel row on the final attempt so the chain steps past it. A
  chain that broke leaving nothing enqueued is resumed by
  `Mehungry.Science.PipelineWatchdog`.
  """

  use Oban.Worker, queue: :imports, max_attempts: 3

  require Logger

  alias Mehungry.Literature
  alias Mehungry.Literature.ConditionCrawlRuns

  @batch_size 10

  @pace_ms Application.compile_env(:mehungry, :entrez_pace_ms, 300)
  @max_snooze_seconds Application.compile_env(:mehungry, :entrez_max_snooze_seconds, 3600)

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, attempt: attempt, max_attempts: max_attempts}) do
    run_id = Map.get(args, "run_id")
    ConditionCrawlRuns.mark_processing(run_id)

    case Literature.list_uncrawled_conditions(@batch_size) do
      [] ->
        Logger.info("ConditionCrawlWorker: all phase-sensitive conditions crawled")
        ConditionCrawlRuns.mark_completed(run_id, Literature.condition_crawl_progress())
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
        Logger.warning("ConditionCrawlWorker: rate-limited, snoozing #{seconds}s")
        {:snooze, seconds}

      {:error, condition_id, reason} when final_attempt? ->
        Logger.error(
          "ConditionCrawlWorker: condition #{condition_id} failed every attempt " <>
            "(#{inspect(reason)}) — marking errored and skipping so the run can continue"
        )

        skip_poison_condition(condition_id)
        advance(run_id)

      {:error, _condition_id, reason} ->
        Logger.warning("ConditionCrawlWorker: transient failure, will retry — #{inspect(reason)}")
        ConditionCrawlRuns.mark_failed(run_id, reason)
        {:error, reason}
    end
  end

  defp advance(run_id) do
    ConditionCrawlRuns.update_progress(run_id, Literature.condition_crawl_progress())
    enqueue_next_batch(run_id)
    :ok
  end

  defp crawl_all(batch) do
    batch
    |> Enum.reduce_while({:ok, 0}, fn condition, {:ok, idx} ->
      pace(idx)

      case Literature.crawl_condition(condition.id) do
        {:ok, _studies_found} ->
          {:cont, {:ok, idx + 1}}

        {:error, {:rate_limited, retry_after}} ->
          {:halt, {:snooze, clamp_snooze(retry_after)}}

        {:error, reason} ->
          {:halt, {:error, condition.id, reason}}
      end
    end)
    |> case do
      {:ok, _count} -> :ok
      other -> other
    end
  end

  # Ledger a sentinel attempt so `list_uncrawled_conditions/1` stops re-selecting it.
  defp skip_poison_condition(condition_id) do
    Literature.record_condition_crawl_attempt(%{
      condition_id: condition_id,
      search_term: "(skipped after repeated crawl failure)",
      outcome: "error",
      studies_found: 0,
      last_crawled_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
  end

  defp final_attempt?(attempt, max_attempts), do: attempt >= max_attempts

  defp pace(0), do: :ok
  defp pace(_idx), do: Process.sleep(@pace_ms)

  defp clamp_snooze(retry_after) when is_integer(retry_after) do
    retry_after |> max(1) |> min(@max_snooze_seconds)
  end

  defp clamp_snooze(_), do: @max_snooze_seconds

  defp enqueue_next_batch(run_id) do
    %{"run_id" => run_id} |> new() |> Oban.insert!()
  end
end
