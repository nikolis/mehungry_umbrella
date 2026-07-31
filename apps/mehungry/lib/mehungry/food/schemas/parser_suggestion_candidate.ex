defmodule Mehungry.Food.ParserSuggestionCandidate do
  @moduledoc """
  A review-gated semantic suggestion — never a fact.

  For a low-confidence deterministic parse (`IngredientParsedFood`), the semantic
  layer (`Mehungry.AI.SemanticMatcher`) proposes that the unresolved
  `surface_text` most likely maps to an existing `CanonicalFood`
  (`suggested_canonical_food_id` / `suggested_target`) at cosine `score`.
  Accepting it grows the parser vocabulary through the existing alias path;
  rejecting keeps it for history. Mirrors the candidate lifecycle of
  `IngredientParsedFood`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Food.{CanonicalFood, IngredientParsedFood}

  @statuses ~w(candidate accepted rejected)
  @kinds ~w(canonical_food merge)

  schema "parser_suggestion_candidates" do
    field :suggestion_kind, :string, default: "canonical_food"
    field :surface_text, :string
    field :suggested_target, :string
    field :score, :float
    field :status, :string, default: "candidate"
    field :model_version, :string
    field :reviewed_by_user_id, :id
    field :reviewed_at, :utc_datetime
    field :notes, :string

    belongs_to :ingredient_parsed_food, IngredientParsedFood
    belongs_to :suggested_canonical_food, CanonicalFood

    timestamps()
  end

  def statuses, do: @statuses
  def kinds, do: @kinds

  def changeset(candidate, attrs) do
    candidate
    |> cast(attrs, [
      :ingredient_parsed_food_id,
      :suggestion_kind,
      :surface_text,
      :suggested_target,
      :suggested_canonical_food_id,
      :score,
      :status,
      :model_version,
      :reviewed_by_user_id,
      :reviewed_at,
      :notes
    ])
    |> validate_required([
      :ingredient_parsed_food_id,
      :surface_text,
      :suggested_target,
      :score,
      :status,
      :model_version
    ])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:suggestion_kind, @kinds)
    |> unique_constraint([:ingredient_parsed_food_id, :suggested_target, :suggestion_kind],
      name: :one_suggestion_per_parse_target_kind
    )
  end
end
