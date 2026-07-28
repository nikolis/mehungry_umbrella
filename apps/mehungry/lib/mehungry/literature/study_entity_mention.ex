defmodule Mehungry.Literature.StudyEntityMention do
  @moduledoc """
  An entity extracted from a `ScientificStudy` by NCBI PubTator3 — a Chemical,
  Species, or Disease mentioned in the paper — recorded as a first-class fact.

  It captures **only what was extracted**: the `entity_type`, the
  `normalized_identifier` PubTator assigned (MeSH for chemicals/diseases as the
  primary identity, NCBI Taxonomy for species), the preserved original `text_span`,
  the `offset` of the mention, and a `confidence` when the annotator supplies one.

  No relationship is inferred. For a chemical whose MeSH id resolved through
  `Mehungry.Chemistry.Resolver`, `compound_id` links the mention to the canonical
  compound — an *identity* link (normalization), never a dietary assertion.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Food.Compound
  alias Mehungry.Literature.ScientificStudy

  @entity_types ~w(chemical species disease)

  @type t :: %__MODULE__{}

  schema "study_entity_mentions" do
    field :entity_type, :string
    field :normalized_identifier, :string
    field :text_span, :string
    field :offset, :integer
    field :confidence, :float
    field :source, :string, default: "pubtator3"

    belongs_to :study, ScientificStudy
    belongs_to :compound, Compound

    timestamps()
  end

  def changeset(mention, attrs) do
    mention
    |> cast(attrs, [
      :study_id,
      :entity_type,
      :normalized_identifier,
      :text_span,
      :offset,
      :confidence,
      :source,
      :compound_id
    ])
    |> validate_required([:study_id, :entity_type, :text_span])
    |> validate_inclusion(:entity_type, @entity_types)
    |> unique_constraint([:study_id, :entity_type, :normalized_identifier, :offset],
      name: :study_entity_mentions_natural_key_index
    )
  end
end
