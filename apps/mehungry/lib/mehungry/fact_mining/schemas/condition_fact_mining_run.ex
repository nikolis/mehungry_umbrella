defmodule Mehungry.FactMining.ConditionFactMiningRun do
  @moduledoc """
  One per-condition tracking row of a "Mine all conditions" fan-out, grouped by
  `batch_id`. Its `ConditionFactMiningWorker` job advances it
  `pending → processing → completed | failed` and records how many facts it stored
  (`facts_total`, plus the `verified`/`contradicted` convenience counts for the
  badge). The admin LiveView streams these rows and derives aggregate batch
  progress by counting over `batch_id`. The condition-scope twin of
  `SpeciesFactMiningRun`. See `docs/implementation/fact_mining.md`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Health.Condition

  @statuses ~w(pending processing completed failed)

  # The runs context stamps every column (incl. inserted_at/updated_at via
  # Repo.insert_all / update_all) with a `DateTime` — keep the auto-timestamps
  # :utc_datetime so those bulk writes validate.
  @timestamps_opts type: :utc_datetime

  schema "condition_fact_mining_runs" do
    field :batch_id, :string
    field :status, :string, default: "pending"
    field :facts_total, :integer, default: 0
    field :verified_count, :integer, default: 0
    field :contradicted_count, :integer, default: 0
    field :error, :string
    field :query, :string
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime

    belongs_to :condition, Condition

    timestamps()
  end

  @castable ~w(batch_id condition_id status facts_total verified_count
               contradicted_count error query started_at completed_at)a

  def changeset(run, attrs) do
    run
    |> cast(attrs, @castable)
    |> validate_required([:batch_id, :condition_id, :status])
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:condition_id)
    |> unique_constraint([:batch_id, :condition_id],
      name: :condition_fact_mining_runs_batch_condition_index
    )
  end

  @doc "The valid `status` values."
  def statuses, do: @statuses
end
