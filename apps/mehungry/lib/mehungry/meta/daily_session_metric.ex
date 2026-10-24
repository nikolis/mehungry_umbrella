defmodule Mehungry.Meta.DailySessionMetric do
  @moduledoc """
  Daily aggregate of anonymous session metrics.

  One row per calendar day (in `Mehungry.Meta.reporting_timezone/0`) with only
  two counters — `session_count` and `total_duration_seconds`. There is no
  per-user or per-session row and no identifying column anywhere; average
  session length is `total_duration_seconds / session_count`. It is
  consent-independent — it counts 100% of connected traffic including visitors
  who declined the cookie banner, which is the one thing Google Analytics
  cannot measure.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "daily_session_metrics" do
    field :date, :date
    field :session_count, :integer, default: 0
    field :total_duration_seconds, :integer, default: 0

    timestamps()
  end

  @doc false
  def changeset(metric, attrs) do
    metric
    |> cast(attrs, [:date, :session_count, :total_duration_seconds])
    |> validate_required([:date])
  end
end
