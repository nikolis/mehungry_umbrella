defmodule Mehungry.MealPlanJobs do
  @moduledoc """
  Durable tracking rows for the mobile API's asynchronous "Plan with AI" flow
  (spec §9). A job is created `queued`, moves to `generating`, then `done` (with
  a result summary) or `error`. The mobile client polls
  `GET /meals/plan-with-ai/:job_id` or subscribes to the `meal_plan:<user_id>`
  channel for live progress.
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

  @doc """
  Fails a job that has been `generating` for longer than any real run can take,
  so a polling client always reaches a terminal state. Any other job is returned
  unchanged. A worker that does finish late still overwrites this with `done`.
  """
  def fail_if_stale(job, now \\ NaiveDateTime.utc_now())

  def fail_if_stale(%MealPlanJob{status: "generating"} = job, now) do
    if NaiveDateTime.diff(now, job.updated_at) > @stale_after_seconds do
      case update_job(job, %{status: "error", error: "generation timed out"}) do
        {:ok, failed} -> failed
        {:error, _} -> job
      end
    else
      job
    end
  end

  def fail_if_stale(job, _now), do: job

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
