defmodule Mehungry.Literature.StudyFullText do
  @moduledoc """
  Fetched PMC open-access full text for a `ScientificStudy` — the source the
  measurement extractor reads (composition numbers live in results/tables, not the
  abstract). One row per study.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Literature.ScientificStudy

  schema "study_full_texts" do
    field :pmcid, :string
    field :source, :string
    field :body, :string
    field :retrieved_at, :utc_datetime

    belongs_to :study, ScientificStudy

    timestamps()
  end

  def changeset(full_text, attrs) do
    full_text
    |> cast(attrs, [:study_id, :pmcid, :source, :body, :retrieved_at])
    |> validate_required([:study_id, :body])
    |> unique_constraint(:study_id)
  end
end
