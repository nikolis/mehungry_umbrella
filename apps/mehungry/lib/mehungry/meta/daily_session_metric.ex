defmodule Mehungry.Meta.DailySessionMetric do
  @moduledoc """
  Daily aggregate of anonymous session metrics.

  One row per calendar day (in `Mehungry.Meta.reporting_timezone/0`) with only
  two counters — `session_count` and `total_duration_seconds`. There is no
  per-user or per-session row and no identifying column anywhere; average visit
  length is `total_duration_seconds / session_count`.

  `session_count` is a count of **real visits** — `Mehungry.Meta.SessionAggregator`
  aggregates connected traffic by a per-tab token and folds a visit in only if it
  was engaged, lasted >=10s, or spanned >=2 views (GA4-parity), dropping
  single-shot/idle/bot loads. It is consent-independent — it counts qualifying
  traffic including visitors who declined the cookie banner, which is the one
  thing Google Analytics cannot measure.
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
