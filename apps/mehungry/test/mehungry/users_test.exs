defmodule Mehungry.UsersTest do
  use Mehungry.DataCase

  alias Mehungry.Users

  alias Mehungry.AccountsFixtures
  alias Mehungry.FoodFixtures

  describe "Listing users created recipes" do
    test "listing user created recipes" do
      user = AccountsFixtures.user_fixture()
      user2 = AccountsFixtures.user_fixture()

      _recipe = FoodFixtures.recipe_fixture(user)
      _recipe1 = FoodFixtures.recipe_fixture(user)
      _recipe2 = FoodFixtures.recipe_fixture(user)
      _recipe3 = FoodFixtures.recipe_fixture(user)
      _recipe4 = FoodFixtures.recipe_fixture(user2)

      recipes = Users.list_user_created_recipes(user)
      assert length(recipes) == 4
    end
  end

  describe "user can save recipes test" do
    test "create user_recipes with valid attrs" do
      user = AccountsFixtures.user_fixture()
      user2 = AccountsFixtures.user_fixture()
      recipe = FoodFixtures.recipe_fixture(user2)
      {:ok, user_recipe} = Users.save_user_recipe(user, recipe)
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

      {:ok, _user_recipe} = Users.save_user_recipe(user, recipe)
      {:ok, _user_recipe2} = Users.save_user_recipe(user, recipe2)
      {:ok, _user_recipe1} = Users.save_user_recipe(user, recipe1)

      user_saved_recipes = Users.list_user_saved_recipes(user)
      assert length(user_saved_recipes) == 3
    end
  end
end
