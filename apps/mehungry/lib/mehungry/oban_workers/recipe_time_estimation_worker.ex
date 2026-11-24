defmodule Mehungry.ObanWorkers.RecipeTimeEstimationWorker do
  @moduledoc """
  One batch of an "Estimate missing times" run (`Mehungry.Food.RecipeTimeEstimation`):
  estimates the next 20 pending recipes with `AI.RecipeTimeEstimator`, writes the
  results (empty fields only, every attempted recipe stamped), bumps the run's
  progress and re-enqueues itself until nothing is pending. Always terminates: an
  attempted recipe is never pending again. Same self-re-enqueueing shape as
  `RecipeMealRoleClassificationWorker`.
  """

  use Oban.Worker, queue: :ai_agents, max_attempts: 3

  require Logger

  alias Mehungry.AI.RecipeTimeEstimator
  alias Mehungry.Food.RecipeTimeEstimation

  @batch_size 20

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"run_id" => run_id}}) do
    RecipeTimeEstimation.mark_processing(run_id)

    case RecipeTimeEstimation.pending_ids(limit: @batch_size) do
      [] ->
        RecipeTimeEstimation.mark_completed(run_id)
        :ok

      ids ->
        inputs = RecipeTimeEstimation.estimator_inputs(ids)

        case RecipeTimeEstimator.impl().estimate(inputs) do
          {:ok, estimates} ->
            Enum.each(ids, &RecipeTimeEstimation.apply_estimate(&1, Map.get(estimates, &1, %{})))
            RecipeTimeEstimation.add_processed(run_id, length(ids))
            %{"run_id" => run_id} |> new() |> Oban.insert!()
            :ok

          {:error, reason} ->
            Logger.warning("RecipeTimeEstimationWorker: batch failed: #{inspect(reason)}")
            RecipeTimeEstimation.mark_failed(run_id, reason)
            {:error, reason}
        end
    end
  end
end
