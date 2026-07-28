defmodule Mehungry.ObanWorkers.BrandedIngredientDeleteWorker do
  @moduledoc """
  Deletes every USDA "Branded" ingredient (and its dependent rows) in the
  background. This is a heavy bulk delete over hundreds of thousands of
  ingredients plus millions of dependent rows, so it must never run inline in a
  web request — it would blow past query timeouts and block the LiveView.

  One singleton job at a time (`unique` across the enqueued/running states). It
  broadcasts progress on `Food.branded_delete_topic/0` so the admin UI can react:
  `:started` when it begins, then `{:completed, {ingredient_count, recipe_count}}`
  or `{:failed, reason}`. Returns `:ok` on success and `{:error, reason}` on
  failure so Oban records the error (no automatic retry — a partial cascade
  already committed, so a blind retry is not meaningful).
  """

  use Oban.Worker,
    queue: :imports,
    max_attempts: 1,
    unique: [
      states: [:available, :scheduled, :executing, :retryable]
    ]

  require Logger

  alias Mehungry.Food

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.info("[BrandedDelete] starting bulk delete of USDA branded ingredients")
    Food.broadcast_branded_delete(:started)

    case Food.delete_branded_ingredients() do
      {:ok, {ingredient_count, recipe_count}} ->
        Logger.info(
          "[BrandedDelete] done: #{ingredient_count} ingredient(s), #{recipe_count} recipe(s)"
        )

        Food.broadcast_branded_delete({:completed, {ingredient_count, recipe_count}})
        :ok

      {:error, reason} ->
        Logger.error("[BrandedDelete] failed: #{inspect(reason)}")
        Food.broadcast_branded_delete({:failed, reason})
        {:error, reason}
    end
  rescue
    e ->
      Logger.error(
        "[BrandedDelete] raised: #{Exception.message(e)}\n" <>
          Exception.format_stacktrace(__STACKTRACE__)
      )

      Food.broadcast_branded_delete({:failed, Exception.message(e)})
      {:error, Exception.message(e)}
  end

  @doc """
  Enqueues the singleton branded-delete job. Returns the `Oban.insert` result;
  the `unique` constraint means a second enqueue while one is pending/running
  returns the existing job rather than starting a duplicate.
  """
  def enqueue do
    %{}
    |> new()
    |> Oban.insert()
  end
end
