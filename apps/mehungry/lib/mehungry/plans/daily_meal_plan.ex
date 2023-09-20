defmodule Mehungry.Plans.DailyMealPlan do
  @moduledoc false

  alias Mehungry.Plans.MealPlan
  alias Mehungry.Plans.Meal

  use Ecto.Schema
  import Ecto.Changeset

  schema "daily_meal_plans" do
    field :daily_meal_plan_title, :string
    field :increasing_number, :integer
    field :meal_note, :string

    has_many :meals, Meal

    belongs_to :meal_plan, MealPlan
    timestamps()
  end

  @doc false
  def changeset(daily_meal_plan, attrs) do
    daily_meal_plan
    |> cast(attrs, [:daily_meal_plan_title, :increasing_number])
    |> validate_required([:increasing_number])
    |> cast_assoc(:meals, with: &Meal.changeset/2, required: true)
  end
end
