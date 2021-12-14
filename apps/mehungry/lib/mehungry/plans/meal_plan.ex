defmodule Mehungry.Plans.MealPlan do
  use Ecto.Schema
  import Ecto.Changeset

  alias Mehungry.Plans.DailyMealPlan

  schema "meal_plans" do
    field :description, :string
    field :title, :string
    field :user_id, :id

    has_many :daily_meal_plans, DailyMealPlan, foreign_key: :meal_plan_id
    timestamps()
  end

  @doc false
  def changeset(meal_plan, attrs) do
    meal_plan
    |> cast(attrs, [:title, :description])
    |> validate_required([:title, :description])
    |> cast_assoc(:daily_meal_plans, with: &DailyMealPlan.changeset/2, required: true)
  end
end
