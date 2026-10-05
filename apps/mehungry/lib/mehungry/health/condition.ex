defmodule Mehungry.Health.Condition do
  @moduledoc """
  A health condition as a first-class reference entity — e.g. *Kidney Stones*,
  *IBS*, *Gout*, *Histamine Intolerance*.

  A shared registry (like `Mehungry.Food.Compound`): one row per condition with a
  canonical `name`, its `synonyms` (abbreviations/aliases such as
  `"Irritable Bowel Syndrome"`), an optional `category` and finer `subcategory`
  (e.g. *Endocrine → Diabetes*), and an optional factual `description`.

  A condition is linked to bioactive compounds — never to ingredients — through
  `CompoundRecommendation`. Any ingredient-facing answer ("which foods should a
  kidney-stone patient avoid?") is derived by composing that link with the food
  layer at read time.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Health.{CompoundRecommendation, ConditionIdentifier}

  @type t :: %__MODULE__{}

  schema "conditions" do
    field :name, :string
    field :synonyms, {:array, :string}, default: []
    field :category, :string
    field :subcategory, :string
    field :description, :string

    # Optional broader condition this is a subtype of (e.g. Ulcerative Colitis →
    # Inflammatory Bowel Disease). The parent's general suggestions are surfaced
    # under the child, labelled.
    belongs_to :parent, __MODULE__, foreign_key: :parent_condition_id
    has_many :children, __MODULE__, foreign_key: :parent_condition_id

    has_many :compound_recommendations, CompoundRecommendation
    # Disease states / phases (e.g. Active Flare vs Remission); most conditions have none.
    has_many :states, Mehungry.Health.ConditionState
    # Cross-database identity (mesh/icd…), written only via Mehungry.Health.
    has_many :identifiers, ConditionIdentifier
    # Per-language name/description translations.
    has_many :translations, Mehungry.Health.ConditionTranslation

    timestamps()
  end

  def changeset(condition, attrs) do
    condition
    |> cast(attrs, [:name, :synonyms, :category, :subcategory, :description, :parent_condition_id])
    |> validate_required([:name])
    |> unique_constraint(:name)
    |> foreign_key_constraint(:parent_condition_id)
  end
end
