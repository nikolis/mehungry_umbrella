defmodule Mehungry.Literature.StudyCondition do
  @moduledoc """
  A discovered link between a `ScientificStudy` and a `Health.Condition`, with the
  exact search term that surfaced it as provenance — the condition analogue of
  `StudyIngredient`.

  Produced by the reverse, condition-seeded crawl: a paper found for
  `"Ulcerative Colitis diet"` records a `StudyCondition` for that condition carrying
  the term. One row per `(study, condition, search_term)`. Powers the
  "Research on this condition" presentation and feeds the phase-aware extraction
  pipeline (which condition a study was crawled for).
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Health.Condition
  alias Mehungry.Literature.ScientificStudy

  @sources ~w(pubmed manual)

  schema "study_conditions" do
    field :search_term, :string
    field :source, :string, default: "pubmed"

    belongs_to :study, ScientificStudy
    belongs_to :condition, Condition

    timestamps()
  end

  def changeset(study_condition, attrs) do
    study_condition
    |> cast(attrs, [:study_id, :condition_id, :search_term, :source])
    |> validate_required([:study_id, :condition_id, :search_term])
    |> validate_inclusion(:source, @sources)
    |> unique_constraint([:study_id, :condition_id, :search_term])
  end
end
