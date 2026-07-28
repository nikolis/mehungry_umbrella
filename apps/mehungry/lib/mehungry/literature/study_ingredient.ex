defmodule Mehungry.Literature.StudyIngredient do
  @moduledoc """
  A discovered link between a `ScientificStudy` and an existing ingredient, with
  the exact search term that surfaced it as provenance.

  A paper found for `"Spinacia oleracea oxalate"` records a `StudyIngredient` for
  the spinach ingredient carrying that `search_term` and a snapshot of the
  `scientific_name` used. One row per `(study, ingredient, search_term)` — the
  same paper can be re-discovered under different terms without duplication.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Food.Ingredient
  alias Mehungry.Literature.ScientificStudy

  @sources ~w(pubmed manual)

  schema "study_ingredients" do
    field :search_term, :string
    field :scientific_name, :string
    field :source, :string, default: "pubmed"

    belongs_to :study, ScientificStudy
    belongs_to :ingredient, Ingredient

    timestamps()
  end

  def changeset(study_ingredient, attrs) do
    study_ingredient
    |> cast(attrs, [:study_id, :ingredient_id, :search_term, :scientific_name, :source])
    |> validate_required([:study_id, :ingredient_id, :search_term])
    |> validate_inclusion(:source, @sources)
    |> unique_constraint([:study_id, :ingredient_id, :search_term])
  end
end
