defmodule Mehungry.RutilsTest do
  use Mehungry.DataCase

  alias Mehungry.Users
  alias Mehungry.Languages
  alias Mehungry.FdcFoodParser
  alias Mehungry.Food

  alias Mehungry.AccountsFixtures
  alias Mehungry.FoodFixtures
  alias Mehungry.Food.RecipeUtils

  defp create_ingredients(_) do
    {:ok, _lang} = Languages.create_language(%{name: "En"})

    FdcFoodParser.get_ingredients_from_food_data_central_json_file(
      "/home/nikolis/Documents/foundationDownload.json"
    )
  end

  describe "Listing users created recipes" do
    setup [:create_ingredients]

    test "listing user created recipes" do
      user = AccountsFixtures.user_fixture()

      _beans = Enum.at(Food.search_ingredient("beans", nil), 0)

      chicken =
        Enum.at(Food.search_ingredient("Chicken, breast, boneless, skinless, raw", nil), 0)

      _beef = Enum.at(Food.search_ingredient("beef", nil), 0)
      broccoli = Enum.at(Food.search_ingredient("Broccoli", nil), 0)
      oil = Enum.at(Food.search_ingredient("oil", nil), 0)
      _cheese = Enum.at(Food.search_ingredient("cheese", nil), 0)

      mu = FoodFixtures.measurement_unit_fixture()

      {:ok, recipe} =
        %{
          title: "some title",
          user_id: user.id,
          author: "another author",
          cousine: "some cusine",
          description: "some description",
          servings: 4,
          difficulty: 1,
          cooking_time_lower_limit: 5,
          preperation_time_lower_limit: 5,
          language_name: "En",
          recipe_ingredients: [
            %{ingredient_id: oil.id, measurement_unit_id: mu.id, quantity: 5},
            %{ingredient_id: chicken.id, measurement_unit_id: mu.id, quantity: 5},
            %{ingredient_id: broccoli.id, measurement_unit_id: mu.id, quantity: 5}
          ]
        }
        |> Food.create_recipe()

      ing_table = RecipeUtils.calculate_recipe_ingredient_categories_array(recipe)

      assert ing_table == [
               "Fats and Oils",
               "Poultry Products",
               "Vegetables and Vegetable Products"
             ]
    end
  end

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
