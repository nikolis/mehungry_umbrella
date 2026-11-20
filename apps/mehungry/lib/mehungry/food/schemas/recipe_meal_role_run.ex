defmodule Mehungry.Food.RecipeMealRoleRun do
  @moduledoc """
  Tracks one recipe meal-role classification run — the self-re-enqueueing chain
  of `RecipeMealRoleClassificationWorker` batches behind one "Classify" click on
  `/professional/recipe-meal-roles`. Mirrors `TaxonomyClassificationRun`.

    * `mode` — `"unclassified"` (recipes never classified) or `"unreviewed"`
      (re-classify every recipe with no reviewed role)
    * `status` — `pending → processing → completed | failed`
    * `processed` / `total` — progress counters for the live bar
  """

  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(pending processing completed failed)
  @modes ~w(unclassified unreviewed)

  schema "recipe_meal_role_runs" do
    field :mode, :string, default: "unclassified"
    field :status, :string, default: "pending"
    field :processed, :integer, default: 0
    field :total, :integer, default: 0
    field :error, :string
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime

    timestamps()
  end

  def modes, do: @modes

  def changeset(run, attrs) do
    run
    |> cast(attrs, [:mode, :status, :processed, :total, :error, :started_at, :completed_at])
    |> validate_required([:mode, :status])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:mode, @modes)
  end
end
