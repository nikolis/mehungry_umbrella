defmodule Mehungry.MealBlueprints.BlueprintPlan do
  @moduledoc """
  A single generation run of a `Blueprint`: the AI planner produced a 7-day plan
  honouring the blueprint's targets. Its contents live in `BlueprintPlanMeal`
  rows and are **independent of the calendar** — the plan lands on the calendar
  only when the user explicitly imports it (which creates `History.UserMeal`
  rows stamped with `blueprint_plan_id`). `imported_at` flags whether that has
  happened (re-import is allowed).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(generating completed failed)

  schema "meal_blueprint_plans" do
    field :name, :string
    field :start_date, :date
    # generating → completed | failed
    field :status, :string, default: "generating"
    field :meals_count, :integer, default: 0
    field :error, :string
    # Set the first time the plan is imported to the calendar (nil = never).
    field :imported_at, :naive_datetime

    # Populated by `MealBlueprints.list_plans_for_blueprint/2` for accordion
    # display — the plan's `BlueprintPlanMeal` rows (recipes/ingredients loaded).
    field :meals, {:array, :map}, virtual: true, default: []

    belongs_to :blueprint, Mehungry.MealBlueprints.Blueprint
    belongs_to :user, Mehungry.Accounts.User

    has_many :plan_meals, Mehungry.MealBlueprints.BlueprintPlanMeal, on_delete: :delete_all

    timestamps()
  end

  @doc false
  def changeset(plan, attrs) do
    plan
    |> cast(attrs, [
      :name,
      :start_date,
      :status,
      :meals_count,
      :error,
      :imported_at,
      :blueprint_id,
      :user_id
    ])
    |> validate_required([:name, :start_date, :status, :blueprint_id, :user_id])
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:blueprint_id)
    |> foreign_key_constraint(:user_id)
  end
end
