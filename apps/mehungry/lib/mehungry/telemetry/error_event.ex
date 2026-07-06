defmodule Mehungry.Telemetry.ErrorEvent do
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
