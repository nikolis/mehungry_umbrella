defmodule Mehungry.ObanWorkers.IngredientIdentityResolutionWorker do
  @moduledoc """
  Resolves ingredients to external scientific identities, one batch per run tick.

  Mirrors `TaxonomyClassificationWorker`: a single job threads a `run_id` through
  a self-re-enqueueing chain, refreshing the run's progress each batch until every
  fdc-backed ingredient has been attempted, then marking the run `completed`.

  Termination is guaranteed by the attempt ledger — `resolve_ingredient/1` records
  an attempt for every processed ingredient (matched, no-name, or definitive
  error), and the next batch excludes anything already attempted.

  Retries are handled by Oban (`max_attempts: 3`): a transient failure
  (rate-limit / network) from `resolve_ingredient/1` marks the run `failed` and
  returns `{:error, reason}`, so Oban retries with backoff. The retry is
  idempotent because already-attempted ingredients are skipped.
  """

  use Oban.Worker, queue: :imports, max_attempts: 3

  require Logger

  alias Mehungry.Food.IdentityResolution
  alias Mehungry.Food.IdentityResolutionRuns

  @batch_size 25

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    run_id = Map.get(args, "run_id")
    IdentityResolutionRuns.mark_processing(run_id)

    case IdentityResolution.list_unresolved_ingredients(@batch_size) do
      [] ->
        Logger.info("IngredientIdentityResolutionWorker: all fdc-backed ingredients attempted")
        IdentityResolutionRuns.mark_completed(run_id, IdentityResolution.resolution_progress())
        :ok

      batch ->
        process_batch(batch, run_id)
    end
  end

  defp process_batch(batch, run_id) do
    case resolve_all(batch) do
      :ok ->
        IdentityResolutionRuns.update_progress(run_id, IdentityResolution.resolution_progress())
        enqueue_next_batch(run_id)
        :ok

      {:error, reason} ->
        Logger.warning(
          "IngredientIdentityResolutionWorker: transient failure, will retry — #{inspect(reason)}"
        )

        IdentityResolutionRuns.mark_failed(run_id, reason)
        {:error, reason}
    end
  end

  # Resolve each ingredient in order; stop the batch on the first transient error
  # so Oban retries (already-attempted rows are skipped on the retry).
  defp resolve_all(batch) do
    Enum.reduce_while(batch, :ok, fn ingredient, :ok ->
      case IdentityResolution.resolve_ingredient(ingredient) do
        {:ok, _outcome} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp enqueue_next_batch(run_id) do
    %{"run_id" => run_id} |> new() |> Oban.insert!()
  end
end
