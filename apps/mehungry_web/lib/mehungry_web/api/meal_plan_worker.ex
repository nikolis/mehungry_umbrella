defmodule MehungryWeb.Api.MealPlanWorker do
  @moduledoc """
  Runs one asynchronous "plan my own week" generation (`UserMealPlanAgent`) for
  **every** client of that feature — the web calendar, blueprint plans, and the
  mobile API (spec §9). One code path, so the surfaces cannot drift, and the run
  lives in Oban rather than in a page's process: leaving the page never cancels
  it.

  It generates the plan, then either writes it to the user's calendar (honouring
  the job's existing-meals `mode`) or stores it on an independent blueprint plan
  (`blueprint_plan_id`), records quota usage, updates the `MealPlanJob` tracking
  row, and broadcasts to `meal_plan:<user_id>` — the topic both the mobile
  channel and the LiveViews follow. Lives in the web app so it can broadcast
  through `MehungryWeb.Endpoint`.

  Runs on its own `:ai_interactive` queue — a person is waiting on it, so it must
  not queue behind batch work on `:ai_agents`. A crash marks the tracking row
  `error` (never left `generating`); a hard kill is caught by
  `MealPlanJobs.fail_if_stale/1` on the next poll / page mount.
  """
  use Oban.Worker, queue: :ai_interactive, max_attempts: 1

  require Logger

  alias Mehungry.AI.Agents.MealPlanCore
  alias Mehungry.AI.MealPlanGenerator
  alias Mehungry.MealBlueprints
  alias Mehungry.MealPlanJobs
  alias Mehungry.Subscriptions

  @doc """
  Creates the tracking row and enqueues its job in one transaction. `attrs` are
  `MealPlanJob` attrs (`user_id`, `start_date`, `notes`, and optionally
  `blueprint_id`, `blueprint_plan_id`, `mode`). Returns `{:ok, job}` or
  `{:error, reason}`.
  """
  def enqueue(attrs) do
    attrs
    |> Map.put_new(:status, "queued")
    |> MealPlanJobs.create_and_enqueue(&new(%{"job_id" => &1.id}))
  end

  @doc "The topic a user's generation progress is broadcast on."
  def topic(user_id), do: "meal_plan:#{user_id}"

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"job_id" => job_id}}) do
    case MealPlanJobs.get_job(job_id) do
      nil -> :ok
      job -> run_safely(job)
    end
  end

  # A hung generation is killed here rather than holding the queue's only slot
  # until Lifeline rescues it at 30 minutes.
  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(8)

  # Anything raised or thrown below must still land the tracking row in `error`:
  # with `max_attempts: 1` there is no retry to fix it up later.
  defp run_safely(job) do
    run(job)
  rescue
    exception ->
      Logger.error(
        "MealPlanWorker crashed: " <> Exception.format(:error, exception, __STACKTRACE__)
      )

      fail(job, :crashed)
      {:error, exception}
  catch
    kind, reason ->
      Logger.error("MealPlanWorker crashed: " <> Exception.format(kind, reason, __STACKTRACE__))
      fail(job, :crashed)
      {:error, {kind, reason}}
  end

  defp run(job) do
    {:ok, job} = MealPlanJobs.update_job(job, %{status: "generating"})
    broadcast(job, "progress", %{status: "generating", pct: 10})

    start_date = job.start_date || Date.utc_today()

    with {:ok, blueprint} <- load_blueprint(job),
         {:ok, plan} <-
           MealPlanGenerator.generate_plan(
             job.notes || "",
             start_date,
             job.user_id,
             blueprint,
             generation_opts(job)
           ),
         {:ok, result} <- deliver(job, plan.entries, start_date) do
      result = Map.merge(result, calorie_report(plan))

      Subscriptions.record_usage(job.user_id, "meal_plan")

      {:ok, _} = MealPlanJobs.update_job(job, %{status: "done", result: result})
      broadcast(job, "result", %{status: "done", meals: result})
      :ok
    else
      {:error, reason} ->
        Logger.warning("MealPlanWorker: generation failed: #{inspect(reason)}")
        fail(job, reason)
        # Surfaced to the client via the tracking row; don't retry (max_attempts: 1).
        :ok
    end
  end

  # The range the plan was held to and any day it could not bring inside it
  # (string keys/dates: this is stored as the job's JSON result). Empty when the
  # run had no calorie target.
  defp calorie_report(%{calorie_band: %{min: min, max: max}} = plan) do
    %{
      "calorie_range" => %{"min" => min, "max" => max},
      "calorie_warnings" =>
        Enum.map(plan.calorie_warnings, &%{"date" => &1.date, "total_kcal" => &1.total})
    }
  end

  defp calorie_report(_plan), do: %{}

  # A requested blueprint that can no longer be resolved fails the run: planning
  # on without it would silently drop its diet / avoid constraints.
  defp load_blueprint(%{blueprint_id: nil}), do: {:ok, nil}

  defp load_blueprint(%{blueprint_id: id, user_id: user_id}) do
    {:ok, MealBlueprints.get_blueprint_for_generation(user_id, id)}
  rescue
    Ecto.NoResultsError -> {:error, :blueprint_unavailable}
  end

  # A calendar run tells the agent its mode (a week-replacing plan must cover
  # every day's main meals); a blueprint plan has no week to replace.
  # A calendar run never plans the already-past days of a running week.
  defp generation_opts(%{blueprint_plan_id: nil, mode: mode} = job),
    do: [mode: MealPlanGenerator.parse_mode(mode), from: plan_from(job)]

  defp generation_opts(_job), do: []

  defp plan_from(job), do: MealPlanGenerator.plan_from(job.start_date || Date.utc_today())

  # Calendar target: write the entries in the job's existing-meals mode.
  defp deliver(%{blueprint_plan_id: nil} = job, entries, start_date) do
    case MealPlanGenerator.persist_entries_to_calendar(
           entries,
           job.user_id,
           start_date,
           job.mode,
           from: plan_from(job)
         ) do
      {:ok, [], _skipped} ->
        {:error, :no_meals_created}

      {:ok, created, skipped} ->
        {:ok,
         %{
           "created_count" => length(created),
           "skipped_count" => skipped,
           "meal_ids" => Enum.map(created, & &1.id)
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Blueprint-plan target: store the entries on the independent plan.
  defp deliver(%{blueprint_plan_id: plan_id} = job, entries, _start_date) do
    plan = MealBlueprints.get_plan!(job.user_id, plan_id)
    MealBlueprints.store_plan_meals(plan, entries)

    {:ok, %{"created_count" => length(entries), "blueprint_plan_id" => plan_id}}
  end

  defp fail(job, reason) do
    message = error_message(reason)

    MealPlanJobs.update_job(job, %{status: "error", error: String.slice(message, 0, 500)})
    fail_blueprint_plan(job, message)
    broadcast(job, "progress", %{status: "error", error: message})
  end

  defp error_message(:blueprint_unavailable), do: "That blueprint is no longer available."
  defp error_message(reason), do: MealPlanCore.error_message(reason)

  defp fail_blueprint_plan(%{blueprint_plan_id: nil}, _message), do: :ok

  defp fail_blueprint_plan(%{blueprint_plan_id: plan_id, user_id: user_id}, message) do
    plan = MealBlueprints.get_plan!(user_id, plan_id)
    MealBlueprints.update_plan(plan, %{status: "failed", error: message})
  rescue
    Ecto.NoResultsError -> :ok
  end

  defp broadcast(job, event, payload) do
    payload =
      Map.merge(payload, %{job_id: job.id, blueprint_plan_id: job.blueprint_plan_id})

    MehungryWeb.Endpoint.broadcast(topic(job.user_id), event, payload)
  end
end
