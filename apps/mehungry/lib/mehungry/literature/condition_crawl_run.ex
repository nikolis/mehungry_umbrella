defmodule Mehungry.Literature.ConditionCrawlRun do
  @moduledoc """
  Aggregate progress record for one reverse (condition-seeded) crawl pass —
  the condition analogue of `CrawlRun`. `processed`/`total` are a coverage snapshot
  refreshed each batch; `status` moves `pending → processing → completed` (or
  `failed`). Broadcast on every transition for a live progress bar.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @statuses ~w(pending processing completed failed)

  schema "condition_crawl_runs" do
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
    |> cast(attrs, [:status, :processed, :total, :studies_found, :error, :started_at, :completed_at])
    |> validate_required([:status])
    |> validate_inclusion(:status, @statuses)
  end
end
