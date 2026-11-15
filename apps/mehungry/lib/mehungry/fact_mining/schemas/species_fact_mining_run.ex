defmodule Mehungry.FactMining.SpeciesFactMiningRun do
  @moduledoc """
  One per-species tracking row of a "Mine all species" fan-out, grouped by
  `batch_id`. Its `SpeciesFactMiningWorker` job advances it
  `pending → processing → completed | failed` and records how many facts it stored
  (`facts_total`, plus the `verified`/`contradicted` convenience counts for the
  badge). The admin LiveView streams these rows and derives aggregate batch
  progress by counting over `batch_id`. See `docs/implementation/fact_mining.md`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Food.FoundementalFoodSpecies

  @statuses ~w(pending processing completed failed)

  schema "species_fact_mining_runs" do
    field :batch_id, :string
    field :status, :string, default: "pending"
    field :facts_total, :integer, default: 0
    field :verified_count, :integer, default: 0
    field :contradicted_count, :integer, default: 0
    field :error, :string
    field :query, :string
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime

    belongs_to :species, FoundementalFoodSpecies, foreign_key: :foundemental_species_id

    timestamps()
  end

  @castable ~w(batch_id foundemental_species_id status facts_total verified_count
               contradicted_count error query started_at completed_at)a

  def changeset(run, attrs) do
    run
    |> cast(attrs, @castable)
    |> validate_required([:batch_id, :foundemental_species_id, :status])
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:foundemental_species_id)
    |> unique_constraint([:batch_id, :foundemental_species_id],
      name: :species_fact_mining_runs_batch_species_index
    )
  end

  @doc "The valid `status` values."
  def statuses, do: @statuses
end
