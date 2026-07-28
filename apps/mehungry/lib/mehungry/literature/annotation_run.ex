defmodule Mehungry.Literature.AnnotationRun do
  @moduledoc """
  Aggregate progress record for one PubTator3 annotation pass over the pool of
  discovered studies. Mirrors `Literature.CrawlRun`: `processed`/`total` are a
  coverage snapshot refreshed each batch, and `status` moves
  `pending → processing → completed` (or `failed`). Broadcast on every transition
  so an admin view can render live progress.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @statuses ~w(pending processing completed failed)

  schema "pubtator_annotation_runs" do
    field :status, :string, default: "pending"
    field :processed, :integer
    field :total, :integer
    field :mentions_found, :integer
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
      :mentions_found,
      :error,
      :started_at,
      :completed_at
    ])
    |> validate_required([:status])
    |> validate_inclusion(:status, @statuses)
  end
end
