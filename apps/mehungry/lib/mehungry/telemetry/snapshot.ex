defmodule Mehungry.Telemetry.Snapshot do
  @moduledoc """
  Ecto schema for `telemetry_snapshots` — the 5-minute aggregate rows flushed
  from `Mehungry.Telemetry.MetricsBuffer`'s in-memory ETS buffer.

  Each row is one `{metric, tags}` pair's min/avg/max/p95 over one flush
  window (`period_start`), e.g. `metric: "phoenix.request.duration"`,
  `tags: %{"route" => "/recipes/:id"}`. `sample_count` is the number of raw
  telemetry events folded into the row. Read by the LiveDashboard
  "Metrics History" and "Endpoints" pages; pruned after 30 days by
  `Mehungry.ObanWorkers.TelemetryPrunerWorker`.

  Rows are written exclusively via `Repo.insert_all/3` in `MetricsBuffer`,
  not through `changeset/2` — the changeset exists for admin/console use and
  as a validation reference.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "telemetry_snapshots" do
    field :metric, :string
    field :tags, :map, default: %{}
    field :period_start, :utc_datetime
    field :min, :float
    field :avg, :float
    field :max, :float
    field :p95, :float
    field :sample_count, :integer
  end

  @doc """
  Casts and validates the fields a flush row needs: `metric`, `period_start`,
  and `sample_count` are required; the min/avg/max/p95 numbers and `tags` are
  optional so callers can build partial snapshots.

  ## Examples

      iex> attrs = %{metric: "phoenix.request.duration", period_start: ~U[2024-01-01 00:00:00Z], sample_count: 12, avg: 42.5}
      iex> Mehungry.Telemetry.Snapshot.changeset(%Mehungry.Telemetry.Snapshot{}, attrs).valid?
      true

      iex> Mehungry.Telemetry.Snapshot.changeset(%Mehungry.Telemetry.Snapshot{}, %{}).valid?
      false

  """
  def changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, [:metric, :tags, :period_start, :min, :avg, :max, :p95, :sample_count])
    |> validate_required([:metric, :period_start, :sample_count])
  end
end
