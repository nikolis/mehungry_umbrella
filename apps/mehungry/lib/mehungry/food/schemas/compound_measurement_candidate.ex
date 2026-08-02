defmodule Mehungry.Food.CompoundMeasurementCandidate do
  @moduledoc """
  A *proposed* quantitative measurement extracted from a study's text by the
  full-text (PMC) + local-QA pipeline — staged `pending → accepted | rejected`.

  Deliberately separate from the immutable `CompoundMeasurement` facts table: the
  extractor never writes facts directly. On **accept** it is materialized via
  `Food.record_measurement/1` against a representative curated ingredient of the
  species (measurements are ingredient-keyed but roll up to the species for scoring).
  Keyed on the species, since extraction associates a compound value with a food
  species, not a specific USDA variant.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Food.{Compound, CompoundMeasurement, FoundementalFoodSpecies}
  alias Mehungry.Literature.ScientificStudy

  @statuses ~w(pending accepted rejected)
  @extraction_methods ~w(automated pdf manual)

  schema "compound_measurement_candidates" do
    field :value, :float
    field :unit, :string
    field :preparation_method, :string
    field :analytical_method, :string
    field :sample_size, :integer
    field :score, :float
    field :raw_span, :string
    field :extraction_method, :string, default: "automated"
    field :status, :string, default: "pending"

    belongs_to :species, FoundementalFoodSpecies, foreign_key: :foundemental_species_id
    belongs_to :compound, Compound
    belongs_to :study, ScientificStudy
    belongs_to :accepted_measurement, CompoundMeasurement

    timestamps()
  end

  @castable ~w(foundemental_species_id compound_id study_id value unit preparation_method
               analytical_method sample_size score raw_span extraction_method status
               accepted_measurement_id)a

  def changeset(candidate, attrs) do
    candidate
    |> cast(attrs, @castable)
    |> validate_required([:foundemental_species_id, :compound_id, :study_id, :value, :unit])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:extraction_method, @extraction_methods)
    |> foreign_key_constraint(:foundemental_species_id)
    |> foreign_key_constraint(:compound_id)
    |> foreign_key_constraint(:study_id)
    |> unique_constraint(
      [:study_id, :foundemental_species_id, :compound_id, :value, :unit],
      name: :compound_measurement_candidates_natural_key_index
    )
  end
end
