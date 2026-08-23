defmodule Mehungry.ObanWorkers.HashtagReconciliationWorker do
  @moduledoc """
  Reconciles one recipe's hashtags, tracked end-to-end.

  One job == one recipe: it runs `Mehungry.Food.ensure_recipe_hashtags/1` (the
  same additive routine the create/update paths use) to reconnect the recipe's
  description `#tags` and (re)attach `#vegan`/`#vegetarian`, then records the
  outcome on the recipe's `HashtagReconciliation` row. Success returns `:ok`;
  failure returns `{:error, reason}` so Oban records the error and retries up to
  `max_attempts`. The durable row is what lets the reconciliation LiveView re-run
  only the undone recipes.

  Modelled on `Mehungry.ObanWorkers.SeedFileImportWorker`.
  """

  use Oban.Worker,
    queue: :hashtag_reconcile,
    max_attempts: 3,
    unique: [
      # Scope uniqueness to this worker + the recipe_id arg. `:worker` must stay
      # in the fields: other workers (RecipePutNutrients/RecipeImage) also carry
      # a `recipe_id` arg, so keying on args alone would cross-dedupe against them.
      fields: [:worker, :args],
      keys: [:recipe_id],
      states: [:available, :scheduled, :executing, :retryable]
    ]

  require Logger

  alias Mehungry.Food
  alias Mehungry.Food.HashtagReconciliations

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"reconciliation_id" => id, "recipe_id" => recipe_id}}) do
    HashtagReconciliations.mark_processing(id)

    case Food.ensure_recipe_hashtags(recipe_id) do
      {:ok, added} ->
        HashtagReconciliations.mark_completed(id, added)
        :ok

      {:error, :not_found} ->
        # The recipe was deleted after the row was enqueued — nothing to do, and
        # not worth retrying. Record it as failed for visibility.
        HashtagReconciliations.mark_failed(id, :recipe_not_found)
        :ok
    end
  rescue
    error ->
      Logger.error(
        "[HashtagReconciliation] recipe #{inspect(recipe_id)} failed: #{inspect(error)}"
      )

      HashtagReconciliations.mark_failed(id, error)
      {:error, error}
  end

  @doc """
  Enqueues (or resets) reconciliation for one recipe and returns the
  `Oban.insert` result. Upserts the tracking row to `pending` first so the UI
  reflects the queued state before the job starts.
  """
  def enqueue(recipe_id) do
    reconciliation = HashtagReconciliations.upsert_pending(recipe_id)

    %{reconciliation_id: reconciliation.id, recipe_id: recipe_id}
    |> new()
    |> Oban.insert()
  end

  @doc """
  Batch variant of `enqueue/1` for a full-corpus sweep. Upserts every tracking
  row to `pending` in one statement, then inserts all jobs in a single
  `Oban.insert_all`. Returns the number of jobs inserted.

  This replaces a per-recipe `enqueue/1` loop that issued two DB round-trips and,
  with Oban's `insert_trigger`, a `NOTIFY` **per recipe** through the single
  Postgres notifier connection. A full resweep of thousands of recipes could back
  that connection up past its 5s `:listen`/`:leader?` call timeout and cascade the
  whole Oban supervision tree down (see `oban_production_diagnostics.md` §12).
  `insert_all` collapses the fan-out to two statements and a single insert
  notification. The `unique` guard still de-dupes against any jobs already queued.
  """
  def enqueue_all(recipe_ids) do
    reconciliations = HashtagReconciliations.upsert_pending_all(recipe_ids)

    jobs =
      Enum.map(reconciliations, fn %{id: id, recipe_id: recipe_id} ->
        new(%{reconciliation_id: id, recipe_id: recipe_id})
      end)

    case Oban.insert_all(jobs) do
      inserted when is_list(inserted) -> length(inserted)
      _ -> 0
    end
  end
end
