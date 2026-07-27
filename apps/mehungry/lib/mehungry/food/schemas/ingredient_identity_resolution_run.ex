defmodule Mehungry.Food.IngredientIdentityResolutionRun do
  @moduledoc """
  Aggregate progress record for one identity-resolution pass over the fdc-backed
  ingredient pool. Mirrors `TaxonomyClassificationRun`: `resolved`/`total` are a
  coverage snapshot refreshed each batch, and `status` moves
  `pending → processing → completed` (or `failed`). Broadcast on every transition
  so an admin view can render live progress.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @statuses ~w(pending processing completed failed)

  schema "ingredient_identity_resolution_runs" do
    field :status, :string, default: "pending"
    field :resolved, :integer
    field :total, :integer
    field :error, :string
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime

    timestamps()
  end

  def changeset(run, attrs) do
    run
    |> cast(attrs, [:status, :resolved, :total, :error, :started_at, :completed_at])
    |> validate_required([:status])
    |> validate_inclusion(:status, @statuses)
  end
end
