defmodule Mehungry.Food.NutrientRecalculationRun do
  @moduledoc """
  Aggregate progress record for one "recompute all recipe nutrients" pass.

  Mirrors `Mehungry.Food.CandidateDerivationRun`: `total` is fixed at enqueue
  time (one `RecipePutNutrientsWorker` job per recipe), while `completed`/`failed`
  are incremented as each job finishes. `status` moves `processing → completed`
  once `completed + failed == total`. Broadcast on every change so the Recipes
  admin view can render a live progress bar.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @statuses ~w(processing completed failed)

  schema "nutrient_recalculation_runs" do
    field :status, :string, default: "processing"
    field :total, :integer, default: 0
    field :completed, :integer, default: 0
    field :failed, :integer, default: 0
    field :error, :string
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime

    timestamps()
  end

  def changeset(run, attrs) do
    run
    |> cast(attrs, [
      :status,
      :total,
      :completed,
      :failed,
      :error,
      :started_at,
      :completed_at
    ])
    |> validate_required([:status])
    |> validate_inclusion(:status, @statuses)
  end
end
