defmodule Mehungry.Literature.StudyFullText do
  @moduledoc """
  Fetched PMC open-access full text for a `ScientificStudy` — the source the
  measurement extractor reads (composition numbers live in results/tables, not the
  abstract). One row per study.

  `sections` holds the structured outline the enriched `mehungry_extractor`
  `/analyze` response carries for a full-text paper: an ordered list of section
  maps (`section_id`, `index`, `title`, `start_char`, `end_char`, `paragraphs`),
  each paragraph `{ paragraph_id, start_char, end_char, text }` with absolute
  offsets into the canonical document text. This powers the nutritionist research
  reader (per-section/paragraph anchors + claim-span highlighting). Empty for
  abstract-only papers.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Literature.ScientificStudy

  schema "study_full_texts" do
    field :pmcid, :string
    field :source, :string
    field :body, :string
    field :sections, {:array, :map}, default: []
    field :retrieved_at, :utc_datetime

    belongs_to :study, ScientificStudy

    timestamps()
  end

  def changeset(full_text, attrs) do
    full_text
    |> cast(attrs, [:study_id, :pmcid, :source, :body, :sections, :retrieved_at])
    |> validate_required([:study_id, :body])
    |> unique_constraint(:study_id)
  end
end
