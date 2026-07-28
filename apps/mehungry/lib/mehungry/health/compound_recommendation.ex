defmodule Mehungry.Health.CompoundRecommendation do
  @moduledoc """
  A dietary recommendation linking a health `Condition` to a `Compound` —
  e.g. *Kidney Stones → avoid → Oxalate*, *IBS → limit → FODMAP*.

  This is the **advice** layer the "facts only" compound docs
  (`docs/food_compounds.md` §4) deliberately defer to: `recommendation` and
  `severity` express guidance, which the `Food.*` fact layers never do. The hard
  rule — a recommendation references a **compound**, never an ingredient — keeps it
  decoupled from ingredient data; the food a patient should avoid is derived by
  composing this with `IngredientCompoundRelationship` at read time.

  Provenance-rich (`source`, `evidence_level`) and append-friendly: the same
  `(condition, compound, source)` is deduped (an idempotent correction), but the
  same pairing from a different source is kept as its own row.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Food.Compound
  alias Mehungry.Health.Condition

  @recommendations ~w(avoid limit caution encourage monitor)
  @severities ~w(low moderate high severe)
  # Reuses the labels produced by `Mehungry.Food.EvidenceAggregation`.
  @evidence_levels ~w(strong moderate limited insufficient)
  @sources ~w(manual ai literature guideline)

  @type t :: %__MODULE__{}

  schema "compound_recommendations" do
    field :recommendation, :string
    field :severity, :string
    field :evidence_level, :string
    field :source, :string
    field :notes, :string

    belongs_to :condition, Condition
    belongs_to :compound, Compound

    timestamps()
  end

  def changeset(recommendation, attrs) do
    recommendation
    |> cast(attrs, [
      :condition_id,
      :compound_id,
      :recommendation,
      :severity,
      :evidence_level,
      :source,
      :notes
    ])
    |> validate_required([:condition_id, :compound_id, :recommendation, :source])
    |> validate_inclusion(:recommendation, @recommendations)
    |> validate_inclusion(:severity, @severities)
    |> validate_inclusion(:evidence_level, @evidence_levels)
    |> validate_inclusion(:source, @sources)
    |> unique_constraint([:condition_id, :compound_id, :source])
  end
end
