defmodule Mehungry.Telemetry.QueryProfile do
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

  def changeset(profile, attrs) do
    profile
    |> cast(attrs, [:fingerprint, :query, :source, :period_start, :min, :avg, :max, :p95, :sample_count])
    |> validate_required([:fingerprint, :query, :period_start, :sample_count])
  end
end
