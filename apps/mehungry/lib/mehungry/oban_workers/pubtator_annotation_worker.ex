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
      `{:error, reason}` for Oban backoff **on all but the final attempt**.

  Both are idempotent because already-attempted studies are skipped on the retry.

  ## Poison-pill guard

  A study that *persistently* errors (a PMID PubTator keeps 5xx-ing on, a chemical
  whose resolver keeps failing, an undecodable payload) is never ledgered by
  `annotate_study/1` — by design, so a genuine blip isn't lost. But that same
  study is re-selected newest-first on every retry, so without a bound it wedges
  the whole chain forever: the batch halts on it, the job exhausts its 3 attempts,
  goes `discarded`, and no successor is ever enqueued — the run sits in
  `processing` and every downstream study stays unannotated. This is the classic
  "annotation stuck" failure.

  So on the **final** Oban attempt we stop bubbling and instead ledger the culprit
  study as `"error"` (recording that we tried and gave up) and enqueue the next
  batch, letting the chain step past the pill. Transient blips still get their full
  retry budget first; only a study that fails every attempt is skipped.

  A broken chain that leaves nothing enqueued at all (a hard crash, an OOM, a
  node kill, a deploy mid-batch) can't be recovered from inside the worker — that
  is what `Mehungry.Science.PipelineWatchdog` resumes out-of-band.
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
  def perform(%Oban.Job{args: args, attempt: attempt, max_attempts: max_attempts}) do
    run_id = Map.get(args, "run_id")
    AnnotationRuns.mark_processing(run_id)

    case Literature.list_unannotated_studies(@batch_size) do
      [] ->
        Logger.info("PubTatorAnnotationWorker: all discovered studies annotated")
        AnnotationRuns.mark_completed(run_id, Literature.annotation_progress())
        :ok

      batch ->
        process_batch(batch, run_id, final_attempt?(attempt, max_attempts))
    end
  end

  defp process_batch(batch, run_id, final_attempt?) do
    case annotate_all(batch) do
      :ok ->
        advance(run_id)

      {:snooze, seconds} ->
        Logger.warning(
          "PubTatorAnnotationWorker: rate-limited, snoozing #{seconds}s (retry unannotated studies)"
        )

        {:snooze, seconds}

      # Final attempt on a persistently-failing study: ledger it as an error so the
      # chain can step past the poison pill, then keep going. See the moduledoc.
      {:error, study_id, reason} when final_attempt? ->
        Logger.error(
          "PubTatorAnnotationWorker: study #{study_id} failed every attempt (#{inspect(reason)}) — " <>
            "marking it errored and skipping so the run can continue"
        )

        skip_poison_study(study_id, reason)
        advance(run_id)

      {:error, _study_id, reason} ->
        Logger.warning(
          "PubTatorAnnotationWorker: transient failure, will retry — #{inspect(reason)}"
        )

        AnnotationRuns.mark_failed(run_id, reason)
        {:error, reason}
    end
  end

  # Refresh the coverage snapshot and hand the baton to the next batch.
  defp advance(run_id) do
    AnnotationRuns.update_progress(run_id, Literature.annotation_progress())
    enqueue_next_batch(run_id)
    :ok
  end

  # Annotate each study in order. A rate-limit short-circuits into a snooze (the
  # already-annotated rows are ledgered); any other transient error halts for an
  # Oban retry with backoff, naming the study that failed so the worker can skip it
  # once its retry budget is spent.
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
          {:halt, {:error, study.id, reason}}
      end
    end)
    |> case do
      {:ok, _count} -> :ok
      other -> other
    end
  end

  # Ledger a give-up attempt so `list_unannotated_studies/1` stops re-selecting it.
  defp skip_poison_study(study_id, _reason) do
    Literature.record_annotation_attempt(%{
      study_id: study_id,
      outcome: "error",
      mentions_found: 0,
      last_annotated_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
  end

  defp final_attempt?(attempt, max_attempts), do: attempt >= max_attempts

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
