defmodule Mehungry.MealPlanJobs.MealPlanJob do
  @moduledoc "Tracking row for an async mobile-API meal-plan generation (spec §9)."
  use Ecto.Schema
  import Ecto.Changeset

  schema "api_meal_plan_jobs" do
    field :user_id, :id
    field :status, :string, default: "queued"
    field :start_date, :date
    field :days, :integer
    field :notes, :string
    field :result, :map
    field :error, :string

    timestamps()
  end

  @statuses ~w(queued generating done error)

  def changeset(job, attrs) do
    job
    |> cast(attrs, [:user_id, :status, :start_date, :days, :notes, :result, :error])
    |> validate_required([:user_id, :status])
    |> validate_inclusion(:status, @statuses)
  end
end
