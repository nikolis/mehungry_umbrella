defmodule Mehungry.MealPlanJobs do
  @moduledoc """
  Durable tracking rows for every asynchronous "plan my own week" generation
  (`UserMealPlanAgent`): the web calendar, blueprint plans, and the mobile API
  (spec §9). A job is created `queued`, moves to `generating`, then `done` (with
  a result summary) or `error`. Generation runs in an Oban job, never in the
  page's process, so leaving the page does not cancel it. Clients follow a run on
  the `meal_plan:<user_id>` topic (the mobile channel and the LiveViews share
  it) or poll `GET /meals/plan-with-ai/:job_id`.
  """
  import Ecto.Query, warn: false

  alias Mehungry.Repo
  alias Mehungry.MealPlanJobs.MealPlanJob

  # A generation normally finishes in a couple of minutes and the worker is killed
  # at 8 (`MealPlanWorker.timeout/1`), so a row still `generating` past this was
  # orphaned by a hard kill (deploy restart, timeout) where no rescue could run.
  @stale_after_seconds 600

  @doc """
  Creates the tracking row and enqueues its Oban job in one transaction, so a
  row can never exist without a job behind it. `job_builder` receives the
  inserted row and returns the Oban job changeset (keeps this module unaware of
  the web-side worker). Returns `{:ok, job}` or `{:error, reason}`.
  """
  def create_and_enqueue(attrs, job_builder) when is_function(job_builder, 1) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert(:job, MealPlanJob.changeset(%MealPlanJob{}, attrs))
    |> Oban.insert(:oban_job, fn %{job: job} -> job_builder.(job) end)
    |> Repo.transaction()
    |> case do
      {:ok, %{job: job}} -> {:ok, job}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  # The Oban worker behind every row (kept as a string: the worker lives in the
  # web app, which this app must not depend on).
  @worker "MehungryWeb.Api.MealPlanWorker"
  @live_oban_states ~w(available scheduled executing retryable)
  @live_statuses ~w(queued generating)

  # A blueprint plan is created just before its job row; give that hand-off time
  # before treating a plan with no job as orphaned.
  @plan_grace_seconds 60

  @doc """
  Fails a run that can no longer finish, so a polling client or a re-mounting
  page always reaches a terminal state. Any other job is returned unchanged.

  A `queued`/`generating` row is dead when:

    * no live Oban job stands behind it (cancelled, discarded, or killed — e.g.
      by `MealPlanWorker.timeout/1`), or
    * it has been `generating` for longer than any real run can take.
  """
  def fail_if_stale(job, now \\ NaiveDateTime.utc_now())

  def fail_if_stale(%MealPlanJob{status: status} = job, now) when status in @live_statuses do
    cond do
      status == "generating" and
          NaiveDateTime.diff(now, job.updated_at) > @stale_after_seconds ->
        mark_failed(job, "generation timed out")

      not live_oban_job?(job.id) ->
        mark_failed(job, "Meal plan generation was interrupted. Please try again.")

      true ->
        job
    end
  end

  def fail_if_stale(job, _now), do: job

  defp mark_failed(job, message) do
    # Re-read first: the worker may have finished between our read and now.
    case Repo.get(MealPlanJob, job.id) do
      %MealPlanJob{status: status} = fresh when status in @live_statuses ->
        case update_job(fresh, %{status: "error", error: message}) do
          {:ok, failed} ->
            fail_blueprint_plan(failed, message)
            failed

          {:error, _} ->
            fresh
        end

      other ->
        other || job
    end
  end

  defp live_oban_job?(job_id) do
    Repo.exists?(
      from j in Oban.Job,
        where: j.worker == @worker and j.state in @live_oban_states,
        where: fragment("?->>'job_id' = ?", j.args, ^to_string(job_id))
    )
  end

  @doc """
  Reconciles every in-flight run of `user_id` against reality:

    * each `queued`/`generating` row goes through `fail_if_stale/2`;
    * a blueprint plan still `generating` with no in-flight row behind it (left
      by an earlier flow, or by a row that was failed elsewhere) is marked failed.

  Called when a page that shows runs mounts or re-checks, and before quota is
  counted, so a dead run never blocks a button or eats quota headroom.
  """
  def fail_stale_for_user(user_id) do
    from(j in MealPlanJob, where: j.user_id == ^user_id and j.status in @live_statuses)
    |> Repo.all()
    |> Enum.each(&fail_if_stale/1)

    fail_orphaned_blueprint_plans(user_id)
  end

  defp fail_orphaned_blueprint_plans(user_id) do
    alias Mehungry.MealBlueprints.BlueprintPlan
    cutoff = NaiveDateTime.add(NaiveDateTime.utc_now(), -@plan_grace_seconds)

    live_plan_ids =
      from(j in MealPlanJob,
        where:
          j.user_id == ^user_id and j.status in @live_statuses and
            not is_nil(j.blueprint_plan_id),
        select: j.blueprint_plan_id
      )

    from(p in BlueprintPlan,
      where: p.user_id == ^user_id and p.status == "generating",
      where: p.inserted_at < ^cutoff,
      where: p.id not in subquery(live_plan_ids)
    )
    |> Repo.all()
    |> Enum.each(
      &Mehungry.MealBlueprints.update_plan(&1, %{
        status: "failed",
        error: "Meal plan generation was interrupted. Please try again."
      })
    )
  end

  @doc """
  How many of the user's own-plan runs are still in flight (dead ones are failed
  first). Counted against quota at enqueue — see `check_quota/1`.
  """
  def in_flight_count(user_id) do
    fail_stale_for_user(user_id)

    Repo.aggregate(
      from(j in MealPlanJob, where: j.user_id == ^user_id and j.status in @live_statuses),
      :count
    )
  end

  @doc """
  The `"meal_plan"` quota check every own-plan surface uses before enqueuing.
  Usage is recorded only when a run succeeds, so runs still in flight count
  against the limit here — otherwise several queued runs could all pass the
  check and overshoot it.
  """
  def check_quota(user_id) do
    Mehungry.Subscriptions.check_quota(user_id, "meal_plan", in_flight_count(user_id))
  end

  # A blueprint-plan run that died leaves its plan row "generating" too.
  defp fail_blueprint_plan(%MealPlanJob{blueprint_plan_id: nil}, _message), do: :ok

  defp fail_blueprint_plan(%MealPlanJob{blueprint_plan_id: plan_id}, message) do
    case Repo.get(Mehungry.MealBlueprints.BlueprintPlan, plan_id) do
      %{status: "generating"} = plan ->
        Mehungry.MealBlueprints.update_plan(plan, %{status: "failed", error: message})

      _ ->
        :ok
    end
  end

  @doc """
  The user's in-flight **calendar** generation, if any (newest first; blueprint
  plan runs are excluded). A dead row is failed on the way out, so a re-mounting
  page restores "generating" only for a run that is really alive.
  """
  def active_calendar_job(user_id) do
    from(j in MealPlanJob,
      where:
        j.user_id == ^user_id and j.status in @live_statuses and
          is_nil(j.blueprint_plan_id),
      order_by: [desc: j.id],
      limit: 1
    )
    |> Repo.one()
    |> case do
      nil ->
        nil

      job ->
        case fail_if_stale(job) do
          %MealPlanJob{status: status} = live when status in @live_statuses -> live
          _ -> nil
        end
    end
  end

  def create_job(attrs) do
    %MealPlanJob{}
    |> MealPlanJob.changeset(attrs)
    |> Repo.insert()
  end

  def get_job(id), do: Repo.get(MealPlanJob, id)

  def get_job(id, user_id) do
    Repo.one(from(j in MealPlanJob, where: j.id == ^id and j.user_id == ^user_id))
  end

  def update_job(%MealPlanJob{} = job, attrs) do
    job
    |> MealPlanJob.changeset(attrs)
    |> Repo.update()
  end
end
