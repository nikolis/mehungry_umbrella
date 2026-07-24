defmodule Mehungry.ObanWorkers.IngredientReconciliationWorker do
  @moduledoc """
  Verifies and corrects stored ingredient data against the authoritative USDA
  FoodData Central record, one batch per run, self-re-enqueueing until every row
  has been visited — same shape as
  `Mehungry.ObanWorkers.TaxonomyClassificationWorker`.

  For each ingredient that carries an `fdc_id`, the worker fetches the current
  USDA record by that id (`FdcClient.fetch_food/1`) and rewrites the row's
  nutritional payload and USDA metadata in place via
  `FoodParser.reconcile_ingredient/2` (portions and nutrients are replaced, not
  appended). Rows without an `fdc_id`, or whose USDA lookup fails, are left as-is
  — but every processed row's `version` is still bumped to `target_version/0`.

  Selecting on `version < target` (rather than, say, `fdc_id IS NOT NULL`) is
  what guarantees the pass always terminates: a row is bumped whether or not it
  could be corrected, so it is never re-selected within the same pass. Bump
  `@target_version` in the future to force every row through a fresh pass.

  Rows are processed newest-first so a freshly-imported ingredient is reconciled
  in the very next pass.

  The USDA client is resolved through the `:fdc_client` app-env seam so tests can
  stub the network call; it defaults to `Mehungry.FoodData.Usda.FdcClient`.

  Termination:
    * empty batch (every row already at the target version) → stop.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  import Ecto.Query

  alias Mehungry.Food.Ingredient
  alias Mehungry.FoodData.Usda.{FdcClient, FoodParser}
  alias Mehungry.Repo

  # USDA lookups are one network round-trip per row, so the batch is much smaller
  # than a pure-SQL backfill would use — each pass stays well inside FDC rate
  # limits and the job's runtime stays bounded.
  @batch_size 25

  # Bump this when a future reconciliation pass needs every row reprocessed.
  @target_version 1

  # Rate-management defaults (all overridable via app env — see config/config.exs):
  #   :fdc_pace_ms                       delay between successive USDA lookups
  #   :fdc_rate_floor                    snooze early once remaining quota hits this
  #   :fdc_low_remaining_snooze_seconds  how long to snooze on a low-quota stop
  #   :fdc_max_snooze_seconds            upper bound applied to a 429 Retry-After
  @pace_ms Application.compile_env(:mehungry, :fdc_pace_ms, 250)
  @rate_floor Application.compile_env(:mehungry, :fdc_rate_floor, 5)
  @low_remaining_snooze_seconds Application.compile_env(
                                  :mehungry,
                                  :fdc_low_remaining_snooze_seconds,
                                  120
                                )
  @max_snooze_seconds Application.compile_env(:mehungry, :fdc_max_snooze_seconds, 3600)

  @doc "The version every row converges to once the current pass has handled it."
  def target_version, do: @target_version

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    case fetch_batch() do
      [] ->
        Logger.info(
          "IngredientReconciliationWorker: all ingredients at version #{@target_version}"
        )

        :ok

      ingredients ->
        process_batch(ingredients)
    end
  end

  # Walk the batch, reconciling one row per USDA round-trip. A rate-limit (a hard
  # 429, or the quota running low) short-circuits into an Oban `{:snooze, _}` so
  # the still-unbumped rows are retried on the next run rather than silently
  # marked done — every other outcome bumps the row's version and advances.
  defp process_batch(ingredients) do
    result =
      Enum.reduce_while(ingredients, {0, nil}, fn ingredient, {done, _remaining} ->
        pace(ingredient, done)

        case reconcile(ingredient) do
          {:snooze, seconds} -> {:halt, {:snooze, seconds}}
          {:ok, remaining} -> continue_or_snooze(done + 1, remaining)
        end
      end)

    case result do
      {:snooze, seconds} ->
        Logger.warning(
          "IngredientReconciliationWorker: rate-limited, snoozing #{seconds}s (retry pending rows)"
        )

        {:snooze, seconds}

      {done, _remaining} ->
        Logger.info("IngredientReconciliationWorker: processed #{done} ingredient(s)")
        enqueue_next_batch()
        :ok
    end
  end

  # Stop the batch early when the API's remaining quota is low: the rows handled
  # so far are already bumped, and a short snooze lets the window refill before
  # the pass resumes. `remaining` is nil for rows recovered from the (unmetered)
  # portal datastore or when the header is absent.
  defp continue_or_snooze(_done, remaining)
       when is_integer(remaining) and remaining <= @rate_floor do
    {:halt, {:snooze, @low_remaining_snooze_seconds}}
  end

  defp continue_or_snooze(done, remaining), do: {:cont, {done, remaining}}

  # Space out USDA calls to smooth bursts under the shared rate budget. Only the
  # rows that actually hit the network are paced, and never before the first one.
  defp pace(%Ingredient{fdc_id: nil}, _done), do: :ok
  defp pace(_ingredient, 0), do: :ok
  defp pace(_ingredient, _done), do: Process.sleep(@pace_ms)

  defp fetch_batch do
    Repo.all(
      from(i in Ingredient,
        where: i.version < ^@target_version,
        order_by: [desc: i.id],
        limit: @batch_size
      )
    )
  end

  # Correct one ingredient from USDA FDC, then bump its version. Returns
  # `{:ok, remaining}` when the row was handled and the pass should advance
  # (`remaining` is the API's leftover quota, or nil), or `{:snooze, seconds}`
  # when the API is rate-limiting and the row must be left unbumped for a retry.
  #
  # The version is bumped in every handled branch — including a missing fdc_id
  # and permanent lookup failures — so the pass always advances and terminates.
  # Only a rate-limit is transient enough to warrant leaving the row behind.
  defp reconcile(%Ingredient{fdc_id: nil} = ingredient) do
    Logger.debug("[Reconciliation] ##{ingredient.id} has no fdc_id — skipping USDA lookup")
    bump_version(ingredient)
    {:ok, nil}
  end

  defp reconcile(%Ingredient{fdc_id: fdc_id} = ingredient) do
    case fdc_client().fetch_food(fdc_id) do
      {:ok, attrs, meta} ->
        case FoodParser.reconcile_ingredient(ingredient, attrs) do
          {:ok, _updated} ->
            Logger.info("[Reconciliation] corrected ##{ingredient.id} (fdcId=#{fdc_id})")

          {:error, reason} ->
            Logger.error(
              "[Reconciliation] update failed for ##{ingredient.id} (fdcId=#{fdc_id}): #{inspect(reason)}"
            )
        end

        bump_version(ingredient)
        {:ok, meta[:remaining]}

      # Transient: leave the row unbumped so it is retried, and tell the caller
      # to snooze the whole job until the quota window recovers.
      {:error, {:rate_limited, retry_after}} ->
        {:snooze, clamp_snooze(retry_after)}

      {:error, reason} ->
        Logger.error(
          "[Reconciliation] FDC lookup failed for ##{ingredient.id} (fdcId=#{fdc_id}): #{inspect(reason)}"
        )

        bump_version(ingredient)
        {:ok, nil}
    end
  end

  # Bound the Retry-After the API advertises: never snooze less than a second,
  # never longer than the configured ceiling (a rate-limited DEMO_KEY can report
  # multi-hour waits).
  defp clamp_snooze(retry_after) when is_integer(retry_after) do
    retry_after |> max(1) |> min(@max_snooze_seconds)
  end

  defp clamp_snooze(_), do: @low_remaining_snooze_seconds

  defp bump_version(%Ingredient{id: id}) do
    Repo.update_all(from(i in Ingredient, where: i.id == ^id), set: [version: @target_version])
  end

  defp enqueue_next_batch do
    %{} |> new() |> Oban.insert!()
  end

  defp fdc_client do
    Application.get_env(:mehungry, :fdc_client, FdcClient)
  end
end
