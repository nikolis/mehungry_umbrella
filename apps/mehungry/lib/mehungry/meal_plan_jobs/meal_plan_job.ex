defmodule Mehungry.MealPlanJobs.MealPlanJob do
  @moduledoc """
  Tracking row for one asynchronous "plan my own week" generation
  (`UserMealPlanAgent`) — the web calendar, blueprint plans, and the mobile API
  (spec §9) all run through it.

    * `blueprint_id` — the blueprint constraining generation (optional).
    * `blueprint_plan_id` — when set, the entries are stored on that independent
      blueprint plan; otherwise they are written to the user's calendar.
    * `mode` — what happens to meals already in the target week: `"fill_gaps"`
      (default) or `"replace_week"`. Calendar target only.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "api_meal_plan_jobs" do
    field :user_id, :id
    field :status, :string, default: "queued"
    field :start_date, :date
    field :days, :integer
    field :notes, :string
    field :blueprint_id, :id
    field :blueprint_plan_id, :id
    field :mode, :string, default: "fill_gaps"
    field :result, :map
    field :error, :string

    timestamps()
  end

  @statuses ~w(queued generating done error)
  @modes ~w(fill_gaps replace_week)

  def changeset(job, attrs) do
    job
    |> cast(attrs, [
      :user_id,
      :status,
      :start_date,
      :days,
      :notes,
      :blueprint_id,
      :blueprint_plan_id,
      :mode,
      :result,
      :error
    ])
    |> validate_required([:user_id, :status])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:mode, @modes)
  end
end
