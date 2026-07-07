defmodule Mehungry.Telemetry.QueryProfile do
  @moduledoc """
  Ecto schema for `query_time_profiles` — per-query-shape aggregates flushed
  from `Mehungry.Telemetry.MetricsBuffer`'s in-memory ETS buffer, powering the
  LiveDashboard "Queries" page.

  Rows are grouped by `fingerprint` (see
  `Mehungry.Telemetry.MetricsBuffer.fingerprint_query/2`) rather than by
  `source` alone, so distinct SQL statements hitting the same table each get
  their own row instead of being averaged together. `query` is the raw SQL
  text (truncated) that produced the fingerprint, kept for display. Pruned
  after 30 days by `Mehungry.ObanWorkers.TelemetryPrunerWorker`.

  Rows are written exclusively via `Repo.insert_all/3` in `MetricsBuffer`,
  not through `changeset/2` — the changeset exists for admin/console use and
  as a validation reference.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "query_time_profiles" do
    field :fingerprint, :string
    field :query, :string
    field :source, :string
    field :period_start, :utc_datetime
    field :min, :float
    field :avg, :float
    field :max, :float
    field :p95, :float
    field :sample_count, :integer
  end

  @doc """
  Casts and validates the fields a flush row needs: `fingerprint`, `query`,
  `period_start`, and `sample_count` are required; `source` and the
  min/avg/max/p95 numbers are optional.

  ## Examples

      iex> attrs = %{fingerprint: "abc123", query: "SELECT 1", period_start: ~U[2024-01-01 00:00:00Z], sample_count: 3}
      iex> Mehungry.Telemetry.QueryProfile.changeset(%Mehungry.Telemetry.QueryProfile{}, attrs).valid?
      true

      iex> Mehungry.Telemetry.QueryProfile.changeset(%Mehungry.Telemetry.QueryProfile{}, %{}).valid?
      false

  """
  def changeset(profile, attrs) do
    profile
    |> cast(attrs, [
      :fingerprint,
      :query,
      :source,
      :period_start,
      :min,
      :avg,
      :max,
      :p95,
      :sample_count
    ])
    |> validate_required([:fingerprint, :query, :period_start, :sample_count])
  end
end
