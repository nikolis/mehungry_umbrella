defmodule Mehungry.Professionals.MealPlanRating do
  use Ecto.Schema
  import Ecto.Changeset

  schema "meal_plan_ratings" do
    field :rating_type, :string
    field :score, :integer
    field :comment, :string
    field :rated_for_date, :date

    belongs_to :user, Mehungry.Accounts.User
    belongs_to :daily_meal_plan, Mehungry.Plans.DailyMealPlan
    belongs_to :meal_plan, Mehungry.Plans.MealPlan

    timestamps()
  end

  def changeset(rating, attrs) do
    rating
    |> cast(attrs, [
      :user_id,
      :rating_type,
      :score,
      :comment,
      :rated_for_date,
      :daily_meal_plan_id,
      :meal_plan_id
    ])
    |> validate_required([:user_id, :rating_type, :score])
    |> validate_inclusion(:rating_type, ["daily", "weekly"])
    |> validate_inclusion(:score, [1, 2, 3, 4, 5])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:daily_meal_plan_id)
    |> foreign_key_constraint(:meal_plan_id)
  end
end
