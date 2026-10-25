defmodule Mehungry.ObanWorkers.IngredientPortionGenerationWorker do
  @moduledoc """
  Generates the derived metric + common-recipe portions for one ingredient
  (`Measurements.generate_portions_for_ingredient/1`).

  Pure DB work — no external API — so it runs on its own `:portion_generation`
  queue (so a full-table sweep can't starve `:default`/`:imports`) and needs no
  rate-limit snooze. Idempotent: a target portion that already exists is left
  untouched, so Oban retries never duplicate rows. Outcome is reported into the
  batch's `IngredientPortionGenerationRun` via the `run_id` arg (absent for
  ad-hoc single enqueues — then the record_* calls no-op). A failure is recorded
  against the run and swallowed so the batch can still finalize.
  """

  use Oban.Worker,
    queue: :portion_generation,
    max_attempts: 3

  require Logger

  alias Mehungry.Food.Measurements
  alias Mehungry.Food.IngredientPortionGenerationRuns, as: Runs

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    ingredient_id = args["ingredient_id"]
    run_id = args["run_id"]

    created = Measurements.generate_portions_for_ingredient(ingredient_id)

    if created > 0 do
      Logger.info(
        "[IngredientPortionGeneration] ingredient #{ingredient_id}: created #{created} portion(s)"
      )
    end

    Runs.record_success(run_id, created)
    :ok
  rescue
    e ->
      Logger.warning(
        "[IngredientPortionGeneration] ingredient #{inspect(args["ingredient_id"])} failed: " <>
          Exception.message(e)
      )

      Runs.record_failure(args["run_id"], Exception.message(e))
      :ok
  end
end
