defmodule Mehungry.Literature.StudyAnalysis do
  @moduledoc """
  The persisted result of the `mehungry_extractor` batch-PMID `/analyze` service
  (see `mehungry_extractor/docs/api.md`) for **one** paper.

  One row per `ScientificStudy` (the paper is the natural key): the paper's
  extracted `claims` (the verbatim `claims_list` — the normalized concept layer
  `/analyze` returns, evidence spans and all), its study/funding facts, and the
  batch-context fields (`status`, `cohesion_score`) from the run that produced
  them. `run` keeps the engine version block for provenance; `content_hash` is a
  stable digest of the meaningful content used to reconcile a re-analysis (see
  `Mehungry.Literature.StudyAnalyses`).

  Extracted claims only — a stored analysis never asserts a dietary fact
  (that stays in the `Food.*` / `Health` layers).
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Literature.ScientificStudy

  @type t :: %__MODULE__{}

  @statuses ~w(included outlier error)

  schema "study_analyses" do
    field :status, :string
    field :error, :string

    field :paper_title, :string
    field :publication_year, :integer
    field :source_type, :string
    field :study_design, :string
    field :sample_size, :integer
    field :funder_types, {:array, :string}, default: []
    field :funding_independence, :string
    field :n_claims, :integer
    field :concept_count, :integer
    field :cohesion_score, :float

    field :claims, {:array, :map}, default: []
    field :run, :map, default: %{}
    field :content_hash, :string
    field :analyzed_at, :utc_datetime

    belongs_to :study, ScientificStudy

    timestamps()
  end

  def changeset(analysis, attrs) do
    analysis
    |> cast(attrs, [
      :study_id,
      :status,
      :error,
      :paper_title,
      :publication_year,
      :source_type,
      :study_design,
      :sample_size,
      :funder_types,
      :funding_independence,
      :n_claims,
      :concept_count,
      :cohesion_score,
      :claims,
      :run,
      :content_hash,
      :analyzed_at
    ])
    |> validate_required([:study_id, :status, :content_hash])
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint(:study_id)
  end
end
