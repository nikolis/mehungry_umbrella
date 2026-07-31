defmodule Mehungry.Food.CandidateDerivationRun do
  @moduledoc """
  Aggregate progress record for one candidate-derivation pass over the evidence
  pairs. Mirrors `IngredientIdentityResolutionRun`: `processed`/`total` are a
  coverage snapshot refreshed each batch, `promoted_count` accumulates the
  auto-promotions, and `status` moves `pending → processing → completed` (or
  `failed`). Broadcast on every transition so an admin view can render live
  progress.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @statuses ~w(pending processing completed failed)

  schema "candidate_derivation_runs" do
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
