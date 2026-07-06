defmodule Mehungry.Telemetry.ErrorEvent do
  @moduledoc """
  Ecto schema backing `error_events` — the DIY, Sentry-free error tracker
  described in `docs/observability.md`.

  Rows are fingerprint-deduplicated: `Mehungry.Telemetry.ErrorTracker` derives
  `fingerprint` from the error's kind/source/reason and upserts on it,
  bumping `count` and `last_seen` instead of inserting a new row for every
  occurrence. `first_seen`/`last_seen` bound the window an error has been
  observed in; `context` holds a free-form map of extra metadata (e.g.
  request path, job args) captured when the fingerprint was first seen.

  Pruned by `Mehungry.ObanWorkers.TelemetryPrunerWorker` once `last_seen` is
  older than 30 days — so a recurring error survives, but a one-off stops
  being retained a month after its last occurrence.
  """

  use Ecto.Schema

  schema "error_events" do
    field :fingerprint, :string
    field :kind, :string
    field :source, :string
    field :reason, :string
    field :stacktrace, :string
    field :context, :map, default: %{}
    field :count, :integer, default: 1
    field :first_seen, :utc_datetime
    field :last_seen, :utc_datetime
  end
end
