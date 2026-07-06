defmodule Mehungry.Telemetry.Snapshot do
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

  def changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, [:metric, :tags, :period_start, :min, :avg, :max, :p95, :sample_count])
    |> validate_required([:metric, :period_start, :sample_count])
  end
end
