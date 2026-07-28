defmodule Mehungry.Literature.CrawlRun do
  @moduledoc """
  Aggregate progress record for one literature-crawl pass over the pool of
  ingredients with a scientific identity. Mirrors
  `IngredientIdentityResolutionRun`: `processed`/`total` are a coverage snapshot
  refreshed each batch, and `status` moves `pending → processing → completed` (or
  `failed`). Broadcast on every transition so an admin view can render live
  progress.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @statuses ~w(pending processing completed failed)

  schema "literature_crawl_runs" do
    field :status, :string, default: "pending"
    field :processed, :integer
    field :total, :integer
    field :studies_found, :integer
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
      :studies_found,
      :error,
      :started_at,
      :completed_at
    ])
    |> validate_required([:status])
    |> validate_inclusion(:status, @statuses)
  end
end
