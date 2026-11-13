defmodule Mehungry.Food.SpeciesEnrichmentRun do
  @moduledoc """
  One per-species tracking row of an "Enrich all species" fan-out, grouped by
  `batch_id`. Its `Mehungry.ObanWorkers.SpeciesEnrichmentWorker` job advances it
  `pending → processing → completed | failed` and records how many facts it upserted
  per source (`wikidata_count` + `faostat_count`). The admin LiveView streams these
  rows and derives aggregate batch progress by counting over `batch_id`. Mirrors the
  per-unit tracking-row pattern of the "Mine all species" sweep
  (`Mehungry.FactMining.SpeciesFactMiningRun`) — see `oban_ui_connected_worker.md`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Food.FoundementalFoodSpecies

  @statuses ~w(pending processing completed failed)

  schema "species_enrichment_runs" do
    field :batch_id, :string
    field :status, :string, default: "pending"
    field :wikidata_count, :integer, default: 0
    field :faostat_count, :integer, default: 0
    field :error, :string
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime

    belongs_to :species, FoundementalFoodSpecies, foreign_key: :foundemental_species_id

    timestamps()
  end

  @castable ~w(batch_id foundemental_species_id status wikidata_count faostat_count
               error started_at completed_at)a

  def changeset(run, attrs) do
    run
    |> cast(attrs, @castable)
    |> validate_required([:batch_id, :foundemental_species_id, :status])
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:foundemental_species_id)
    |> unique_constraint([:batch_id, :foundemental_species_id],
      name: :species_enrichment_runs_batch_species_index
    )
  end

  @doc "The valid `status` values."
  def statuses, do: @statuses
end
