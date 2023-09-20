defmodule Mehungry.FoodTest do
  use Mehungry.DataCase

  alias Mehungry.History.{UserMeal}
  alias Mehungry.History
  alias Mehungry.{FoodFixtures, AccountsFixtures}

  describe "User Meal Test" do
    test "Create User Meal" do
      user = AccountsFixtures.user_fixture()
      recipe = FoodFixtures.recipe_fixture(user)
      dt_now = NaiveDateTime.utc_now()

      user_meal_params = %{
        start_dt: dt_now,
        end_dt: dt_now,
        title: "Breakfast",
        user_id: user.id,
        recipe_user_meals: [%{recipe_id: recipe.id}]
      }

      result = History.create_user_meal(user_meal_params)
    end
  end
end
