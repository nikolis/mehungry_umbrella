defmodule Mehungry.Plans.Meal do

  alias Mehungry.Plans.DailyMealPlan
  alias Mehungry.Food.Recipe

  use Ecto.Schema
  import Ecto.Changeset

  schema "meals" do
    field :meal_note, :string
    field :meal_title, :string

    belongs_to :recipe, Recipe 
    belongs_to :daily_meal_plan, DailyMealPlan 
    timestamps()
  end

  @doc false
  def changeset(meal, attrs) do
    meal
    |> cast(attrs, [:meal_title, :meal_note, :recipe_id])
    |> validate_required([:meal_title])
  end
end
