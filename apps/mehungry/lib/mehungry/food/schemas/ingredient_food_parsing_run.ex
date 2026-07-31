defmodule Mehungry.Food.IngredientFoodParsingRun do
  @moduledoc """
  Aggregate progress record for one description-parsing pass over the
  fdc-backed ingredient pool. Mirrors `IngredientIdentityResolutionRun`:
  `processed`/`total` are a coverage snapshot refreshed each batch, `status`
  moves `pending → processing → completed` (or `failed`), and every transition
  is broadcast so the admin view renders live progress.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @statuses ~w(pending processing completed failed)

  schema "ingredient_food_parsing_runs" do
    field :status, :string, default: "pending"
    field :processed, :integer
    field :total, :integer
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
