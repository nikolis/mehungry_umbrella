defmodule Mehungry.Literature.AnnotationAttempt do
  @moduledoc """
  A per-study ledger row for PubTator3 annotation.

  One row per `study_id` records the `outcome` (`annotated | no_results | error`),
  the number of `mentions_found`, and `last_annotated_at`. This is what makes the
  batch annotation terminate — already-attempted studies are excluded from the
  next batch — and the mirror of `Literature.CrawlAttempt` for the crawl phase.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Literature.ScientificStudy

  @outcomes ~w(annotated no_results error)

  schema "pubtator_annotation_attempts" do
    field :outcome, :string
    field :mentions_found, :integer, default: 0
    field :last_annotated_at, :utc_datetime

    belongs_to :study, ScientificStudy

    timestamps()
  end

  def changeset(attempt, attrs) do
    attempt
    |> cast(attrs, [:study_id, :outcome, :mentions_found, :last_annotated_at])
    |> validate_required([:study_id, :outcome])
    |> validate_inclusion(:outcome, @outcomes)
    |> unique_constraint(:study_id)
  end
end
