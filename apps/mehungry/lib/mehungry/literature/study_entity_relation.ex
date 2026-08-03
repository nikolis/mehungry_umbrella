defmodule Mehungry.Literature.StudyEntityRelation do
  @moduledoc """
  A directional relation between two entities in a `ScientificStudy`, as extracted
  by NCBI PubTator3 (the per-document `relations` array).

  Where `StudyEntityMention` records *that* an entity appears, this records *how two
  appear together*: the relation `type` — `Negative_Correlation`,
  `Positive_Correlation`, `Association`, `Cotreatment` — carries a directional
  valence that co-occurrence alone cannot. For a chemical↔disease relation this is
  the signal a condition recommendation needs (negative → lean *encourage*,
  positive → lean *avoid/limit*).

  Each endpoint keeps its raw namespaced identifier (`entity1_identifier` /
  `entity2_identifier`, e.g. `"mesh:D007249"`) for audit, and *resolves* where we
  model it: the chemical endpoint to a `Food.Compound` (`compound_id`), the disease
  endpoint to a `Health.Condition` (`condition_id`). Either FK may be nil (a gene
  endpoint, a non-dietary chemical, or an unmatched disease). This is extraction
  only — it never asserts a dietary fact or recommendation.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Food.Compound
  alias Mehungry.Health.Condition
  alias Mehungry.Literature.ScientificStudy

  @type t :: %__MODULE__{}

  schema "study_entity_relations" do
    field :type, :string
    field :score, :float

    field :entity1_type, :string
    field :entity1_identifier, :string
    field :entity1_name, :string
    field :entity2_type, :string
    field :entity2_identifier, :string
    field :entity2_name, :string

    field :source, :string, default: "pubtator3"

    belongs_to :study, ScientificStudy
    belongs_to :compound, Compound
    belongs_to :condition, Condition

    timestamps()
  end

  def changeset(relation, attrs) do
    relation
    |> cast(attrs, [
      :study_id,
      :type,
      :score,
      :entity1_type,
      :entity1_identifier,
      :entity1_name,
      :entity2_type,
      :entity2_identifier,
      :entity2_name,
      :source,
      :compound_id,
      :condition_id
    ])
    |> validate_required([:study_id, :type])
    |> unique_constraint([:study_id, :type, :entity1_identifier, :entity2_identifier],
      name: :study_entity_relations_natural_key_index
    )
  end
end
