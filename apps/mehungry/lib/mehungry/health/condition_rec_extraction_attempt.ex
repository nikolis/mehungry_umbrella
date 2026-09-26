defmodule Mehungry.Health.ConditionRecExtractionAttempt do
  @moduledoc """
  Termination ledger for the phase-aware extraction pipeline: one row per
  `(study, condition)` pair the offline extractor has processed. A pair leaves the
  `condition_pending` set once the service posts back, guaranteeing the batch
  terminates — the recommendation-extraction analogue of `PmcFetchAttempt`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Health.Condition
  alias Mehungry.Literature.ScientificStudy

  schema "condition_rec_extraction_attempts" do
    field :candidates_found, :integer, default: 0

    belongs_to :study, ScientificStudy
    belongs_to :condition, Condition

    timestamps()
  end

  def changeset(attempt, attrs) do
    attempt
    |> cast(attrs, [:study_id, :condition_id, :candidates_found])
    |> validate_required([:study_id, :condition_id])
    |> unique_constraint([:study_id, :condition_id])
  end
end
