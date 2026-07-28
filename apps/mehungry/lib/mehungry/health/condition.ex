defmodule Mehungry.Health.Condition do
  @moduledoc """
  A health condition as a first-class reference entity — e.g. *Kidney Stones*,
  *IBS*, *Gout*, *Histamine Intolerance*.

  A shared registry (like `Mehungry.Food.Compound`): one row per condition with a
  canonical `name`, its `synonyms` (abbreviations/aliases such as
  `"Irritable Bowel Syndrome"`), an optional `category`, and an optional factual
  `description`.

  A condition is linked to bioactive compounds — never to ingredients — through
  `CompoundRecommendation`. Any ingredient-facing answer ("which foods should a
  kidney-stone patient avoid?") is derived by composing that link with the food
  layer at read time.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Health.CompoundRecommendation

  @type t :: %__MODULE__{}

  schema "conditions" do
    field :name, :string
    field :synonyms, {:array, :string}, default: []
    field :category, :string
    field :description, :string

    has_many :compound_recommendations, CompoundRecommendation

    timestamps()
  end

  def changeset(condition, attrs) do
    condition
    |> cast(attrs, [:name, :synonyms, :category, :description])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end
end
