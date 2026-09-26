defmodule Mehungry.Health.ConditionStateRecommendation do
  @moduledoc """
  A **phase-aware** dietary recommendation for a condition — the decoupled,
  state-tagged advice store. A row links a `Condition` (optionally narrowed to a
  `ConditionState` such as *Active Flare*; `nil` = general/all-phase) to a target that
  is a registry `Compound`, a nutrient (canonical `nutrient_name`), or a free-text
  `raw_food_term` (e.g. *"low-residue"*), with a `recommendation`
  (`avoid|limit|caution|encourage|monitor`) and `severity`.

  Deliberately **separate** from `CompoundRecommendation` / `NutrientRecommendation`
  so phase-specific advice never leaks into the shared read surfaces (`/foods`,
  badges, blueprint) until the "combine" step wires it in — it is surfaced only on the
  condition page's phase selector.

  Written by promoting a reviewed `ConditionRecommendationCandidate` (`source:
  "literature"`, its studies frozen) or hand-authored (`source: "manual"`, which must
  carry a `source_reference`). Idempotent on the app-computed `dedup_key`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Food.Compound
  alias Mehungry.Health.{Condition, ConditionState, ConditionStateRecommendationStudy}

  @recommendations ~w(avoid limit caution encourage monitor)
  @severities ~w(low moderate high severe)
  @evidence_levels ~w(strong moderate limited insufficient)
  @sources ~w(literature manual)
  @unsourced_by_study ~w(manual)

  @type t :: %__MODULE__{}

  schema "condition_state_recommendations" do
    field :nutrient_name, :string
    field :raw_food_term, :string
    field :recommendation, :string
    field :severity, :string
    field :evidence_level, :string
    field :source, :string
    field :notes, :string
    field :source_reference, :map
    field :dedup_key, :string

    belongs_to :condition, Condition
    belongs_to :condition_state, ConditionState
    belongs_to :compound, Compound

    has_many :recommendation_studies, ConditionStateRecommendationStudy,
      foreign_key: :recommendation_id

    has_many :studies, through: [:recommendation_studies, :study]

    timestamps()
  end

  def changeset(recommendation, attrs) do
    recommendation
    |> cast(attrs, [
      :condition_id,
      :condition_state_id,
      :compound_id,
      :nutrient_name,
      :raw_food_term,
      :recommendation,
      :severity,
      :evidence_level,
      :source,
      :notes,
      :source_reference,
      :dedup_key
    ])
    |> validate_required([:condition_id, :recommendation, :source, :dedup_key])
    |> validate_inclusion(:recommendation, @recommendations)
    |> maybe_validate_inclusion(:severity, @severities)
    |> maybe_validate_inclusion(:evidence_level, @evidence_levels)
    |> validate_inclusion(:source, @sources)
    |> validate_has_target()
    |> validate_has_citation()
    |> unique_constraint(:dedup_key)
  end

  # Must point at something — a compound, a nutrient name, or a free-text food term.
  defp validate_has_target(changeset) do
    if get_field(changeset, :compound_id) || present?(get_field(changeset, :nutrient_name)) ||
         present?(get_field(changeset, :raw_food_term)) do
      changeset
    else
      add_error(changeset, :raw_food_term, "a compound, nutrient_name, or raw_food_term is required")
    end
  end

  # A manual recommendation carries no frozen PubMed study, so it must supply a
  # structured `source_reference`. Literature sources cite via the frozen study links.
  defp validate_has_citation(changeset) do
    if get_field(changeset, :source) in @unsourced_by_study do
      case get_field(changeset, :source_reference) do
        ref when is_map(ref) and map_size(ref) > 0 -> changeset
        _ -> add_error(changeset, :source_reference, "is required for a manual source")
      end
    else
      changeset
    end
  end

  defp present?(v), do: is_binary(v) and v != ""

  defp maybe_validate_inclusion(changeset, field, allowed) do
    case get_field(changeset, field) do
      nil -> changeset
      _ -> validate_inclusion(changeset, field, allowed)
    end
  end
end
