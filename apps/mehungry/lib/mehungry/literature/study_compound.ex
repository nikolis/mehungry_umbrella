defmodule Mehungry.Literature.StudyCompound do
  @moduledoc """
  A discovered link between a `ScientificStudy` and a registry `Compound`.

  Set only when the search term that surfaced the paper matched a compound in the
  `Mehungry.Food.Compounds` registry (e.g. the `"… oxalate"` term maps to the
  `Oxalate` compound). Generic phytochemistry terms (`"… phytochemical"`) yield a
  `StudyIngredient` link but no `StudyCompound`. One row per `(study, compound)`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Food.Compound
  alias Mehungry.Literature.ScientificStudy

  schema "study_compounds" do
    field :search_term, :string

    belongs_to :study, ScientificStudy
    belongs_to :compound, Compound

    timestamps()
  end

  def changeset(study_compound, attrs) do
    study_compound
    |> cast(attrs, [:study_id, :compound_id, :search_term])
    |> validate_required([:study_id, :compound_id])
    |> unique_constraint([:study_id, :compound_id])
  end
end
