defmodule Mehungry.Food.GlycemicIndexCandidate do
  @moduledoc """
  A *proposed* Glycemic Index value **re-derived from a primary study**, staged
  `pending → promoted | rejected` — the review gate of the path-B GI pipeline
  (see `docs/science/glycemic_index_licensing.md`).

  Mirrors `Food.CompoundMeasurementCandidate`: the local-AI service extracts the
  measured GI from a paper's full text, and each finding is fanned over every
  `FoundementalFoodSpecies` the study links to. The value + `gi_sem` are stored on the
  glucose=100 scale (as GI is universally reported), so promotion writes
  `basis: "glucose=100"`. Nothing becomes a fact until an admin promotes it: promotion
  fans the value onto every ingredient of the species as reviewed
  `IngredientScientificProperty` rows and records their ids in `promoted_property_ids`
  so an Undo deletes exactly those. Provenance is the `study` — there is no table row,
  `quality_tier`, or name-match; `iso_method` (an ISO 26642:2010-consistent method in
  the paper) is the quality signal that, with an exact species link, auto-promotes.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Food.{FoundementalFoodSpecies, Ingredient, IngredientEnrichmentSource}
  alias Mehungry.Literature.ScientificStudy

  @statuses ~w(pending promoted rejected)
  @extraction_methods ~w(automated pdf manual)

  schema "glycemic_index_candidates" do
    field :gi_value, :float
    field :gi_sem, :float
    field :reference_food, :string
    field :sample_size, :integer
    field :country, :string
    field :year, :integer
    field :analytical_method, :string
    field :iso_method, :boolean, default: false

    field :score, :float
    field :raw_span, :string
    field :extraction_method, :string, default: "automated"

    field :status, :string, default: "pending"
    field :promoted_property_ids, {:array, :integer}, default: []

    belongs_to :study, ScientificStudy
    belongs_to :species, FoundementalFoodSpecies, foreign_key: :foundemental_species_id
    belongs_to :ingredient, Ingredient
    belongs_to :enrichment_source, IngredientEnrichmentSource

    timestamps()
  end

  @castable ~w(study_id foundemental_species_id ingredient_id gi_value gi_sem
               reference_food sample_size country year analytical_method iso_method
               score raw_span extraction_method status promoted_property_ids
               enrichment_source_id)a

  def changeset(candidate, attrs) do
    candidate
    |> cast(attrs, @castable)
    |> validate_required([:study_id, :gi_value, :status])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:extraction_method, @extraction_methods)
    |> foreign_key_constraint(:study_id)
    |> foreign_key_constraint(:foundemental_species_id)
    |> foreign_key_constraint(:ingredient_id)
    |> unique_constraint([:study_id, :foundemental_species_id, :gi_value],
      name: :glycemic_index_candidates_natural_key_index
    )
  end
end
