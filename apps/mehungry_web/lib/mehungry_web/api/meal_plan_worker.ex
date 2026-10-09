defmodule MehungryWeb.Api.MealPlanWorker do
  @moduledoc """
  Runs an asynchronous "Plan with AI" generation for the mobile API (spec §9):
  generates a meal plan via `AI.MealPlanGenerator`, persists the meals, records
  quota usage, updates the `MealPlanJob` tracking row, and broadcasts progress to
  the `meal_plan:<user_id>` channel. Lives in the web app so it can broadcast
  through `MehungryWeb.Endpoint`.
  """
  use Oban.Worker, queue: :ai_agents, max_attempts: 1

  require Logger

  alias Mehungry.AI.MealPlanGenerator
  alias Mehungry.Food
  alias Mehungry.MealPlanJobs
  alias Mehungry.Subscriptions

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"job_id" => job_id}}) do
    case MealPlanJobs.get_job(job_id) do
      nil -> :ok
      job -> run(job)
    end
  end

  defp run(job) do
    {:ok, job} = MealPlanJobs.update_job(job, %{status: "generating"})
    broadcast(job.user_id, "progress", %{job_id: job.id, status: "generating", pct: 10})

    recipes = Food.list_user_recipes_for_selection(job.user_id)
    start_date = job.start_date || Date.utc_today()

    case MealPlanGenerator.run(job.notes || "", recipes, start_date, job.user_id, nil) do
      {:ok, created, _skipped} ->
        Subscriptions.record_usage(job.user_id, "meal_plan")

        result = %{"created_count" => length(created), "meal_ids" => Enum.map(created, & &1.id)}
        {:ok, _} = MealPlanJobs.update_job(job, %{status: "done", result: result})
        broadcast(job.user_id, "result", %{job_id: job.id, status: "done", meals: result})
        :ok

      {:error, reason} ->
        {:ok, _} = MealPlanJobs.update_job(job, %{status: "error", error: inspect(reason)})
        broadcast(job.user_id, "progress", %{job_id: job.id, status: "error"})
        # Surfaced to the client via the tracking row; don't retry (max_attempts: 1).
        :ok
    end
  end

  defp broadcast(user_id, event, payload) do
    MehungryWeb.Endpoint.broadcast("meal_plan:#{user_id}", event, payload)
  end
end
