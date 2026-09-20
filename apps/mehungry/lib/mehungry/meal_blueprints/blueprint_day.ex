defmodule Mehungry.MealBlueprints.BlueprintDay do
  @moduledoc """
  One day (ordinal 1..7) of a `Blueprint`. Holds the optional per-day total
  calorie aim and the five per-meal target rows. The "general" targets (required
  and avoid nutrients/compounds, preferred foods) live one level up, on the
  `Blueprint` itself, since they apply across every day. `day_index` is a template
  ordinal, not a calendar date.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Mehungry.MealBlueprints.BlueprintMeal

  schema "meal_blueprint_days" do
    field :day_index, :integer
    field :total_calorie_target, :integer

    belongs_to :blueprint, Mehungry.MealBlueprints.Blueprint

    has_many :meals, BlueprintMeal, foreign_key: :blueprint_day_id, on_replace: :delete

    timestamps()
  end

  @doc false
  def changeset(day, attrs) do
    day
    |> cast(attrs, [:day_index, :total_calorie_target])
    |> validate_required([:day_index])
    |> validate_inclusion(:day_index, 1..7)
    |> validate_number(:total_calorie_target, greater_than_or_equal_to: 0)
    |> cast_assoc(:meals, with: &BlueprintMeal.changeset/2)
  end
end
