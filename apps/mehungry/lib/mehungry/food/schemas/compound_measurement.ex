defmodule Mehungry.Food.CompoundMeasurement do
  @moduledoc """
  A single quantitative measurement of a `Compound` in an `Ingredient`, as
  reported by a research paper — e.g. *Spinach, Oxalate, Raw: 750 mg/100g*.

  Each row is one immutable observation: `value` + `unit` under a stated
  `preparation_method` (Raw, Boiled, …) and `analytical_method` (the lab
  technique the paper used, e.g. HPLC), optionally with the study's
  `sample_size` and a `confidence`. `extraction_method` records how the data
  point entered our system (`manual` entry, `automated` extraction, or `pdf`
  extraction), which is provenance about our pipeline, not the lab.

  **Measurements are immutable.** Historical values are never updated — a new
  study reporting a different value creates a *new* measurement, and the two
  coexist. The changeset here is insert-only (there is no update path in
  `Mehungry.Food.CompoundMeasurements`); aggregation across measurements is a
  separate read-only concern that never mutates these rows.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Food.{Ingredient, Compound}
  alias Mehungry.Literature.ScientificStudy

  # How the measurement entered our system (pipeline provenance) — distinct from
  # `analytical_method`, which is the lab technique the paper itself used.
  @extraction_methods ~w(manual automated pdf)

  @type t :: %__MODULE__{}

  schema "compound_measurements" do
    field :value, :float
    field :unit, :string
    field :preparation_method, :string
    field :analytical_method, :string
    field :sample_size, :integer
    field :confidence, :float
    field :extraction_method, :string
    field :raw_span, :string

    belongs_to :ingredient, Ingredient
    belongs_to :compound, Compound
    # Optional: manual entries may not reference a cataloged study.
    belongs_to :study, ScientificStudy

    timestamps()
  end

  @doc """
  Insert-only changeset. Measurements are immutable, so this validates a new
  observation; there is deliberately no update changeset.
  """
  def changeset(measurement, attrs) do
    measurement
    |> cast(attrs, [
      :ingredient_id,
      :compound_id,
      :study_id,
      :value,
      :unit,
      :preparation_method,
      :analytical_method,
      :sample_size,
      :confidence,
      :extraction_method,
      :raw_span
    ])
    |> validate_required([:ingredient_id, :compound_id, :value, :unit, :extraction_method])
    |> validate_number(:value, greater_than_or_equal_to: 0)
    |> validate_number(:sample_size, greater_than: 0)
    |> validate_number(:confidence, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_inclusion(:extraction_method, @extraction_methods)
    |> foreign_key_constraint(:ingredient_id)
    |> foreign_key_constraint(:compound_id)
    |> foreign_key_constraint(:study_id)
    |> unique_constraint(
      [:study_id, :ingredient_id, :compound_id, :preparation_method, :analytical_method],
      name: :compound_measurements_natural_key_index
    )
  end
end
