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
