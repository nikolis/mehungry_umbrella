defmodule Mehungry.ObanWorkers.IngredientFoodParsingWorker do
  @moduledoc """
  Parses USDA ingredient descriptions into structured candidate rows, one
  batch per run tick.

  Mirrors `IngredientIdentityResolutionWorker`: a single job threads a
  `run_id` through a self-re-enqueueing chain, refreshing the run's progress
  each batch until every fdc-backed ingredient has a parse at the current
  parser version, then marking the run `completed`.

  Termination is guaranteed by the parsed rows themselves — parsing is pure
  (no external I/O) and always writes a row (result or skip), and the next
  batch excludes anything already parsed at the current version. Any raise is
  a bug: Oban retries (`max_attempts: 3`) and the find-or-create write makes
  the retry idempotent.
  """

  use Oban.Worker, queue: :imports, max_attempts: 3

  require Logger

  alias Mehungry.Food.{FoodParsingRuns, ParsedFoods}

  @batch_size 100

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    run_id = Map.get(args, "run_id")
    FoodParsingRuns.mark_processing(run_id)

    case ParsedFoods.list_unparsed_ingredients(@batch_size) do
      [] ->
        Logger.info("IngredientFoodParsingWorker: all fdc-backed ingredients parsed")
        FoodParsingRuns.mark_completed(run_id, ParsedFoods.parsing_progress())
        :ok

      batch ->
        Enum.each(batch, &ParsedFoods.parse_ingredient/1)
        FoodParsingRuns.update_progress(run_id, ParsedFoods.parsing_progress())
        %{"run_id" => run_id} |> new() |> Oban.insert!()
        :ok
    end
  rescue
    exception ->
      FoodParsingRuns.mark_failed(Map.get(args, "run_id"), exception)
      reraise exception, __STACKTRACE__
  end
end
