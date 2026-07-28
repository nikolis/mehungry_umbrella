defmodule Mehungry.ObanWorkers.PubTatorAnnotationWorker do
  @moduledoc """
  Annotates discovered studies with NCBI PubTator3, extracting Chemical / Species /
  Disease entity mentions, one batch per run tick.

  Mirrors `LiteratureCrawlWorker`: a single job threads a `run_id` through a
  self-re-enqueueing chain, refreshing the run's progress each batch until every
  discovered study has been annotated, then marking the run `completed`.

  Termination is guaranteed by the annotation ledger — `annotate_study/1` records
  an attempt for every study it touches, and the next batch excludes any study
  already attempted.

  Retries/rate limits (Oban `max_attempts: 3`):

    * a transient `{:error, {:rate_limited, retry_after}}` short-circuits the batch
      into an Oban `{:snooze, seconds}` so the still-unannotated studies are retried
      later rather than skipped;
    * any other transient `{:error, reason}` marks the run `failed` and returns
      `{:error, reason}` for Oban backoff.

  Both are idempotent because already-attempted studies are skipped on the retry.
  """

  use Oban.Worker, queue: :imports, max_attempts: 3

  require Logger

  alias Mehungry.Literature
  alias Mehungry.Literature.AnnotationRuns

  # Each study is one PubTator round-trip plus per-chemical resolver calls, so the
  # batch is small to keep each pass inside NCBI rate limits.
  @batch_size 10

  # Rate-management defaults (overridable via app env — see config/config.exs):
  #   :pubtator_pace_ms            delay between successive study annotations
  #   :pubtator_max_snooze_seconds upper bound applied to a rate-limit Retry-After
  @pace_ms Application.compile_env(:mehungry, :pubtator_pace_ms, 300)
  @max_snooze_seconds Application.compile_env(:mehungry, :pubtator_max_snooze_seconds, 3600)

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    run_id = Map.get(args, "run_id")
    AnnotationRuns.mark_processing(run_id)

    case Literature.list_unannotated_studies(@batch_size) do
      [] ->
        Logger.info("PubTatorAnnotationWorker: all discovered studies annotated")
        AnnotationRuns.mark_completed(run_id, Literature.annotation_progress())
        :ok

      batch ->
        process_batch(batch, run_id)
    end
  end

  defp process_batch(batch, run_id) do
    case annotate_all(batch) do
      :ok ->
        AnnotationRuns.update_progress(run_id, Literature.annotation_progress())
        enqueue_next_batch(run_id)
        :ok

      {:snooze, seconds} ->
        Logger.warning(
          "PubTatorAnnotationWorker: rate-limited, snoozing #{seconds}s (retry unannotated studies)"
        )

        {:snooze, seconds}

      {:error, reason} ->
        Logger.warning(
          "PubTatorAnnotationWorker: transient failure, will retry — #{inspect(reason)}"
        )

        AnnotationRuns.mark_failed(run_id, reason)
        {:error, reason}
    end
  end

  # Annotate each study in order. A rate-limit short-circuits into a snooze (the
  # already-annotated rows are ledgered); any other transient error halts for an
  # Oban retry with backoff.
  defp annotate_all(batch) do
    batch
    |> Enum.reduce_while({:ok, 0}, fn study, {:ok, idx} ->
      pace(idx)

      case Literature.annotate_study(study.id) do
        {:ok, _mentions_found} ->
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

  # Space out annotations under the shared rate budget; never before the first.
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
