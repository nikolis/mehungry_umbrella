defmodule MehungrySeasonality.Run do
  @moduledoc """
  One per-species tracking row of a "Fetch <country>" fan-out, grouped by `batch_id`.
  Its `MehungrySeasonality.Workers.FetchWorker` job advances it
  `pending → processing → completed | failed` and records how many months of local
  and import data it stored. `species` is a virtual slim map attached on read for
  display. See `docs/reference_architecture/oban_ui_connected_worker.md`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @statuses ~w(pending processing completed failed)

  schema "seasonality_runs" do
    field :batch_id, :string
    field :foundemental_species_id, :integer
    field :country, :string
    field :status, :string, default: "pending"
    field :local_count, :integer, default: 0
    field :import_count, :integer, default: 0
    field :error, :string
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime

    field :species, :map, virtual: true

    timestamps()
  end

  @castable ~w(batch_id foundemental_species_id country status local_count import_count
               error started_at completed_at)a

  def changeset(run, attrs) do
    run
    |> cast(attrs, @castable)
    |> validate_required([:batch_id, :foundemental_species_id, :country, :status])
    |> validate_inclusion(:status, @statuses)
  end

  def statuses, do: @statuses
end
