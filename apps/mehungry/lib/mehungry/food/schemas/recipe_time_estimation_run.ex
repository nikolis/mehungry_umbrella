defmodule Mehungry.Food.RecipeTimeEstimationRun do
  @moduledoc """
  Tracks one "Estimate missing times" run on `/professional/recipe-times` — the
  self-re-enqueueing chain of `RecipeTimeEstimationWorker` batches.

    * `status` — `pending → processing → completed | failed`
    * `processed` / `total` — progress counters for the live bar
  """

  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(pending processing completed failed)

  schema "recipe_time_estimation_runs" do
    field :status, :string, default: "pending"
    field :processed, :integer, default: 0
    field :total, :integer, default: 0
    field :error, :string
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime

    timestamps()
  end

  def changeset(run, attrs) do
    run
    |> cast(attrs, [:status, :processed, :total, :error, :started_at, :completed_at])
    |> validate_required([:status])
    |> validate_inclusion(:status, @statuses)
  end
end
