defmodule Mehungry.Literature.StudyConditionExclusion do
  @moduledoc """
  A persistent flag that a `ScientificStudy` does **not** belong to a
  `Health.Condition` — set when an admin re-assigns a discovered paper to a
  better-fitting condition on `/professional/health`.

  Unlike `StudyCondition` (which is per `(study, condition, search_term)`), an
  exclusion is **term-agnostic**: it keys on `(study, condition)` so the reverse
  (condition-seeded) crawl skips re-linking the paper under *any* search term for
  that condition. This is what stops a re-assigned paper from bouncing back on the
  next re-crawl. `reassigned_to_condition_id` records where it was moved (provenance).
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Health.Condition
  alias Mehungry.Literature.ScientificStudy

  schema "study_condition_exclusions" do
    belongs_to :study, ScientificStudy
    belongs_to :condition, Condition
    belongs_to :reassigned_to_condition, Condition

    timestamps()
  end

  def changeset(exclusion, attrs) do
    exclusion
    |> cast(attrs, [:study_id, :condition_id, :reassigned_to_condition_id])
    |> validate_required([:study_id, :condition_id])
    |> unique_constraint([:study_id, :condition_id])
  end
end
