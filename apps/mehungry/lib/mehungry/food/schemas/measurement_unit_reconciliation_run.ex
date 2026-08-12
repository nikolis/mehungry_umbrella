defmodule Mehungry.Food.MeasurementUnitReconciliationRun do
  @moduledoc """
  Aggregate progress record for one "reconcile numeric-named measurement units"
  pass — a batch of USDA NDB-number lookups.

  Mirrors `Mehungry.Food.NutrientRecalculationRun`: `total` is fixed at enqueue
  time (one `MeasurementUnitReconciliationWorker` job per numeric-named unit),
  while `completed`/`failed` increment as jobs finish. `status` moves
  `processing → completed` once `completed + failed == total`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @statuses ~w(processing completed failed)

  schema "measurement_unit_reconciliation_runs" do
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
    |> cast(attrs, [:status, :total, :completed, :failed, :error, :started_at, :completed_at])
    |> validate_required([:status])
    |> validate_inclusion(:status, @statuses)
  end
end
