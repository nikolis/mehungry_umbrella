defmodule Mehungry.MealBlueprints.BlueprintMeal do
  @moduledoc """
  Per-meal nutritional targets within one day of a `Blueprint`: the macro split
  as **percentages of the meal's energy** — `protein_pct`, `carbs_pct`,
  `fats_pct` — which must always total 100 (default 30 / 40 / 30), plus an
  optional free-text `note`. The "general" targets (required nutrients /
  compounds, preferred foods) live one level up, on
  `Mehungry.MealBlueprints.Blueprint`.

  `meal_type` is one of `Mehungry.History.MealType.values/0` (the same slots the
  calendar supports); validation defers to that single source of truth.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Mehungry.History.MealType

  # Default macro split (protein / carbs / fats), summing to 100 %.
  @default_protein_pct 30
  @default_carbs_pct 40
  @default_fats_pct 30

  schema "meal_blueprint_meals" do
    field :meal_type, :string
    field :protein_pct, :integer, default: @default_protein_pct
    field :carbs_pct, :integer, default: @default_carbs_pct
    field :fats_pct, :integer, default: @default_fats_pct
    field :note, :string

    belongs_to :blueprint_day, Mehungry.MealBlueprints.BlueprintDay

    timestamps()
  end

  @macro_fields [:protein_pct, :carbs_pct, :fats_pct]

  @doc "The default macro split as a map, for skeleton/preset builders."
  def default_split,
    do: %{
      protein_pct: @default_protein_pct,
      carbs_pct: @default_carbs_pct,
      fats_pct: @default_fats_pct
    }

  @doc false
  def changeset(meal, attrs) do
    meal
    |> cast(attrs, [
      :meal_type,
      :protein_pct,
      :carbs_pct,
      :fats_pct,
      :note
    ])
    |> validate_required([:meal_type])
    |> validate_meal_type()
    |> validate_macro_ranges()
    |> validate_macro_total()
  end

  # Couples validation to MealType.values/0 rather than duplicating the list.
  defp validate_meal_type(changeset) do
    validate_change(changeset, :meal_type, fn :meal_type, value ->
      if MealType.valid?(value) and not is_nil(value),
        do: [],
        else: [meal_type: "is not a supported meal slot"]
    end)
  end

  # Each macro is a percentage in 0..100.
  defp validate_macro_ranges(changeset) do
    Enum.reduce(@macro_fields, changeset, fn field, acc ->
      validate_number(acc, field, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    end)
  end

  # The three macro percentages must add up to exactly 100.
  defp validate_macro_total(changeset) do
    total =
      Enum.reduce(@macro_fields, 0, fn field, sum -> sum + (get_field(changeset, field) || 0) end)

    if total == 100 do
      changeset
    else
      add_error(
        changeset,
        :protein_pct,
        "protein + carbs + fats must total 100%%, got #{total}%%"
      )
    end
  end
end
