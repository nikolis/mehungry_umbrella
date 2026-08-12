defmodule Mehungry.RutilsTest do
  use Mehungry.DataCase

  alias Mehungry.Users

  alias Mehungry.AccountsFixtures
  alias Mehungry.FoodFixtures

  describe "user can save recipes test" do
    test "create user_recipes with valid attrs" do
      user = AccountsFixtures.user_fixture()
      user2 = AccountsFixtures.user_fixture()
      recipe = FoodFixtures.recipe_fixture(user2)
      {:ok, user_recipe} = Users.save_user_recipe(user.id, recipe.id)
      assert user_recipe.recipe_id == recipe.id
    end

    test "retrieve user saved recipes" do
      user = AccountsFixtures.user_fixture()
      user2 = AccountsFixtures.user_fixture()
      recipe = FoodFixtures.recipe_fixture(user2)
      recipe1 = FoodFixtures.recipe_fixture(user2)
      recipe2 = FoodFixtures.recipe_fixture(user2)
      _recipe3 = FoodFixtures.recipe_fixture(user2)
      _recipe4 = FoodFixtures.recipe_fixture(user2)

      {:ok, _user_recipe} = Users.save_user_recipe(user.id, recipe.id)
      {:ok, _user_recipe2} = Users.save_user_recipe(user.id, recipe2.id)
      {:ok, _user_recipe1} = Users.save_user_recipe(user.id, recipe1.id)

      user_saved_recipes = Users.list_user_saved_recipes(user)
      assert length(user_saved_recipes) == 3
    end
  end
end
