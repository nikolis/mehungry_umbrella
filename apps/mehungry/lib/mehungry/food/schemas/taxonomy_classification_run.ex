defmodule Mehungry.Food.TaxonomyClassificationRun do
  @moduledoc """
  Tracks one classification run over a taxonomy — the self-re-enqueueing chain of
  `TaxonomyClassificationWorker` batches for a single "Run Classification" click.
  `status` is the lifecycle of the run:

    * `pending`    — enqueued, no batch has started yet
    * `processing` — a worker batch is classifying
    * `completed`  — every ingredient is classified (or nothing usable remained)
    * `failed`     — a batch errored; `error` holds the inspected reason

  `classified`/`total` are a coverage snapshot updated after each batch, so the
  UI can render a live progress bar. Driven by
  `Mehungry.Food.TaxonomyClassificationRuns`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Mehungry.Food.Taxonomy

  @statuses ~w(pending processing completed failed)

  schema "taxonomy_classification_runs" do
    field :status, :string, default: "pending"
    field :classified, :integer
    field :total, :integer
    field :error, :string
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime

    belongs_to :taxonomy, Taxonomy

    timestamps()
  end

  def changeset(run, attrs) do
    run
    |> cast(attrs, [
      :taxonomy_id,
      :status,
      :classified,
      :total,
      :error,
      :started_at,
      :completed_at
    ])
    |> validate_required([:taxonomy_id, :status])
    |> validate_inclusion(:status, @statuses)
  end
end
