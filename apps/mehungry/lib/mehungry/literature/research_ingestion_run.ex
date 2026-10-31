defmodule Mehungry.Literature.ResearchIngestionRun do
  @moduledoc """
  Aggregate progress record for one admin-triggered research-ingestion pass (the
  UI equivalent of `mix research.ingest`): crawl? + extractor `/analyze` + store,
  across conditions.

  The run **fans out** to one `ResearchIngestionWorker` job per condition (so a
  server restart only interrupts the in-flight condition — the rest are
  independent queued jobs that resume on boot, and the interrupted one is rescued
  + retried by Oban). `conditions_total` is fixed at enqueue; `conditions_done`
  and `conditions_failed` advance as each condition's job reports, and the
  aggregate store counters (`inserted`/`updated`/`unchanged`/`skipped`)
  accumulate; `current_condition` names the one most recently started (the queue
  is concurrency 1, so effectively the running one). `status` moves
  `processing → completed` once `conditions_done + conditions_failed ==
  conditions_total` (a few failing conditions can't wedge it) — but `→ failed`
  when **every** condition failed (e.g. the extractor was down the whole run), and
  also `→ failed` when an admin cancels / a stale run is reconciled. `options`
  records the toggles.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @statuses ~w(processing completed failed)

  schema "research_ingestion_runs" do
    field :status, :string, default: "processing"
    field :options, :map, default: %{}
    field :conditions_total, :integer, default: 0
    field :conditions_done, :integer, default: 0
    field :conditions_failed, :integer, default: 0
    field :current_condition, :string
    field :inserted, :integer, default: 0
    field :updated, :integer, default: 0
    field :unchanged, :integer, default: 0
    field :skipped, :integer, default: 0
    field :error, :string
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime

    timestamps()
  end

  def changeset(run, attrs) do
    run
    |> cast(attrs, [
      :status,
      :options,
      :conditions_total,
      :conditions_done,
      :conditions_failed,
      :current_condition,
      :inserted,
      :updated,
      :unchanged,
      :skipped,
      :error,
      :started_at,
      :completed_at
    ])
    |> validate_required([:status])
    |> validate_inclusion(:status, @statuses)
  end
end
