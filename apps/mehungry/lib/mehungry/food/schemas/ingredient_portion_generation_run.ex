defmodule Mehungry.Food.IngredientPortionGenerationRun do
  @moduledoc """
  Aggregate progress record for one "generate derived ingredient portions" pass.

  Mirrors `Mehungry.Food.MeasurementUnitReconciliationRun`: `total` is fixed at
  enqueue time (one `IngredientPortionGenerationWorker` job per ingredient),
  while `completed`/`failed` increment as jobs finish and `portions_created`
  accumulates how many new `IngredientPortion` rows were synthesized. `status`
  moves `processing → completed` once `completed + failed == total`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @statuses ~w(processing completed failed)

  schema "ingredient_portion_generation_runs" do
    field :status, :string, default: "processing"
    field :total, :integer, default: 0
    field :completed, :integer, default: 0
    field :failed, :integer, default: 0
    field :portions_created, :integer, default: 0
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
      :portions_created,
      :error,
      :started_at,
      :completed_at
    ])
    |> validate_required([:status])
    |> validate_inclusion(:status, @statuses)
  end
end
