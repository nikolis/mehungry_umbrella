defmodule Mehungry.Literature.ScientificStudy do
  @moduledoc """
  A research paper discovered on NCBI Entrez (PubMed) as a first-class reference
  entity — the *evidence* connecting an ingredient to a bioactive compound.

  A shared registry (like `Compound`): one row per paper, keyed by its PubMed
  `pmid`. It is linked to ingredients through `StudyIngredient` and to compounds
  through `StudyCompound`. Chemical/bibliographic identity beyond the core columns
  lives in `raw_metadata`; the complete efetch payload is retained in
  `entrez_responses`.

  This layer represents **discovered literature only** — a study's presence never
  asserts a dietary fact (that stays in `IngredientCompoundRelationship`).
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Literature.{StudyIngredient, StudyCompound}

  @type t :: %__MODULE__{}

  schema "scientific_studies" do
    field :pmid, :integer
    field :doi, :string
    field :title, :string
    field :abstract, :string
    field :journal, :string
    field :publication_date, :string
    field :authors, {:array, :string}, default: []
    # Journal-authority signal (nutritionist research search): `issn` is the
    # journal join key; `citation_status` is the MedlineCitation @Status
    # ("MEDLINE" = vetted/indexed) — a public-domain authority marker.
    field :issn, :string
    field :citation_status, :string
    field :raw_metadata, :map, default: %{}
    field :retrieved_at, :utc_datetime

    has_many :study_ingredients, StudyIngredient, foreign_key: :study_id
    has_many :study_compounds, StudyCompound, foreign_key: :study_id

    timestamps()
  end

  def changeset(study, attrs) do
    study
    |> cast(attrs, [
      :pmid,
      :doi,
      :title,
      :abstract,
      :journal,
      :publication_date,
      :authors,
      :issn,
      :citation_status,
      :raw_metadata,
      :retrieved_at
    ])
    |> validate_required([:pmid])
    |> unique_constraint(:pmid)
  end
end
