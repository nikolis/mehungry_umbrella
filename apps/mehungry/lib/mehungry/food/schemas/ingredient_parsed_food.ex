defmodule Mehungry.Food.IngredientParsedFood do
  @moduledoc """
  The structured parse of one ingredient's USDA description at one parser
  version — the persisted form of a `Parser.Result` (or, when `skip_reason` is
  set, a `Parser.Skipped`).

  Mirrors `IngredientScientificIdentity`: rows are append-only candidates the
  admin reviews (and may edit while `candidate`); verifying supersedes any
  previously verified parse for the ingredient via `superseded_by_id`, so
  history is preserved. `canonical_food_text` is always set for non-skipped
  rows; `canonical_food_id` links the lexicon entry once known (set on verify
  at the latest). The row's existence at a given `parser_version` is also the
  batch worker's termination ledger.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Food.{CanonicalFood, Ingredient}

  @statuses ~w(candidate verified rejected superseded)

  schema "ingredient_parsed_foods" do
    field :canonical_food_text, :string
    field :harvest_stage, :string, default: "mature"
    field :processing, {:array, :string}, default: []
    field :processing_modifiers, {:array, :string}, default: []
    field :packaging, :string, default: "na"
    field :part, :string
    field :dismemberment, :string
    field :bone_state, :string
    field :portion, {:array, :string}, default: []
    field :grade, :string
    field :fat, :string
    field :confidence, :float
    field :skip_reason, :string
    field :parser_version, :string
    field :trace, {:array, :map}
    field :status, :string, default: "candidate"
    field :verified_by_user_id, :id
    field :verified_at, :utc_datetime
    field :notes, :string

    belongs_to :ingredient, Ingredient
    belongs_to :canonical_food, CanonicalFood
    belongs_to :superseded_by, __MODULE__

    timestamps()
  end

  def statuses, do: @statuses

  def changeset(parsed_food, attrs) do
    parsed_food
    |> cast(attrs, [
      :ingredient_id,
      :canonical_food_id,
      :canonical_food_text,
      :harvest_stage,
      :processing,
      :processing_modifiers,
      :packaging,
      :part,
      :dismemberment,
      :bone_state,
      :portion,
      :grade,
      :fat,
      :confidence,
      :skip_reason,
      :parser_version,
      :trace,
      :status,
      :verified_by_user_id,
      :verified_at,
      :superseded_by_id,
      :notes
    ])
    |> validate_required([:ingredient_id, :parser_version, :status])
    |> validate_inclusion(:status, @statuses)
    |> validate_food_or_skip()
    |> unique_constraint([:ingredient_id, :parser_version])
    |> unique_constraint(:ingredient_id, name: :one_verified_parsed_food_per_ingredient)
  end

  # A row is either a parse (food text present) or a skip (reason present).
  defp validate_food_or_skip(changeset) do
    food = get_field(changeset, :canonical_food_text)
    skip = get_field(changeset, :skip_reason)

    if is_nil(food) and is_nil(skip) do
      add_error(
        changeset,
        :canonical_food_text,
        "either canonical_food_text or skip_reason is required"
      )
    else
      changeset
    end
  end
end
