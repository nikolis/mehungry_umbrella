defmodule Mehungry.Health.RecommendationDerivationRun do
  @moduledoc """
  Aggregate progress record for one recommendation-candidate derivation pass over
  the condition↔compound relation pairs. Mirrors `Food.CandidateDerivationRun`:
  `processed`/`total` are a coverage snapshot refreshed each batch, and `status`
  moves `pending → processing → completed` (or `failed`). `promoted_count` stays 0 —
  this stage never auto-promotes — but is kept for run-record symmetry. Broadcast on
  every transition for live admin progress.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @statuses ~w(pending processing completed failed)

  schema "recommendation_derivation_runs" do
    field :status, :string, default: "pending"
    field :processed, :integer
    field :total, :integer
    field :promoted_count, :integer, default: 0
    field :error, :string
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime

    timestamps()
  end

  def changeset(run, attrs) do
    run
    |> cast(attrs, [
      :status,
      :processed,
      :total,
      :promoted_count,
      :error,
      :started_at,
      :completed_at
    ])
    |> validate_required([:status])
    |> validate_inclusion(:status, @statuses)
  end
end
