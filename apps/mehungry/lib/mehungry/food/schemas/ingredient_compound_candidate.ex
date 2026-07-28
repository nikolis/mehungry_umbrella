defmodule Mehungry.Food.IngredientCompoundCandidate do
  @moduledoc """
  A *proposed* ingredient↔compound relationship derived from evidence (PubTator
  co-occurrence, compound measurements, or manual import), scored and staged
  through `pending → promoted | rejected`.

  It is deliberately a separate table from `IngredientCompoundRelationship`: the
  facts table stays curated-only, and this holds the messy, unreviewed proposals
  the docs' "human-curation step" reads. Mirrors `IngredientTaxonomyNode`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Food.{Compound, Ingredient, IngredientCompoundRelationship}

  @relationship_types ~w(contains high_in low_in trace absent)
  @statuses ~w(pending promoted rejected)
  @evidence_levels ~w(strong moderate limited insufficient)
  @sources ~w(pubtator measurement manual)

  schema "ingredient_compound_candidates" do
    field :relationship_type, :string, default: "contains"
    field :status, :string, default: "pending"
    field :evidence_score, :float, default: 0.0
    field :evidence_level, :string
    field :study_count, :integer, default: 0
    field :measurement_study_count, :integer, default: 0
    field :sources, {:array, :string}, default: []
    field :evidence, :map, default: %{}
    field :notes, :string

    belongs_to :ingredient, Ingredient
    belongs_to :compound, Compound
    belongs_to :promoted_relationship, IngredientCompoundRelationship

    timestamps()
  end

  @castable ~w(ingredient_id compound_id relationship_type status evidence_score
               evidence_level study_count measurement_study_count sources evidence
               notes promoted_relationship_id)a

  def changeset(candidate, attrs) do
    candidate
    |> cast(attrs, @castable)
    |> validate_required([:ingredient_id, :compound_id, :relationship_type, :status])
    |> validate_inclusion(:relationship_type, @relationship_types)
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:evidence_level, @evidence_levels)
    |> validate_subset(:sources, @sources)
    |> unique_constraint([:ingredient_id, :compound_id, :relationship_type],
      name: :ingredient_compound_candidates_natural_key_index
    )
  end
end
