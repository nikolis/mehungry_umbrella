defmodule Mehungry.UsersTest do
  use Mehungry.DataCase

  alias Mehungry.Users

  alias Mehungry.AccountsFixtures
  alias Mehungry.FoodFixtures
  alias Mehungry.Languages
  alias Mehungry.FdcFoodParser
  alias Mehungry.Food

  @restrictions %{
    "Absolutely not" => 0,
    "Not a fun" => 0.5,
    "Neutral" => 1,
    "Fun" => 1.5,
    "Absolutely fun" => 2
  }

  defp create_ingredients(_) do
    {:ok, _lang} = Languages.create_language(%{name: "En"})

    FdcFoodParser.get_ingredients_from_food_data_central_json_file(
      "/home/nikolis/Documents/foundationDownload.json"
    )

    Enum.each(Map.keys(@restrictions), fn x ->
      Users.create_user_restriction_type(%{title: x, alias: x})
    end)
  end

  describe "Category rules translation " do
    setup [:create_ingredients]

    test "Creatin and list of category_rules" do
      user = AccountsFixtures.user_fixture()
      restrictions = Users.list_food_restriction_types()

      chicken =
        Enum.at(Food.search_ingredient("Chicken, breast, boneless, skinless, raw", nil), 0)

      oil = Enum.at(Food.search_ingredient("oil", nil), 0)
      broccoli = Enum.at(Food.search_ingredient("Broccoli", nil), 0)

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

      Users.create_user_category_rule(%{
        category_id: chicken.category.id,
        food_restriction_type_id: Enum.at(restrictions, 0).id,
        user_id: user.id
      })

      Users.create_user_category_rule(%{
        category_id: broccoli.category.id,
        food_restriction_type_id: Enum.at(restrictions, 2).id,
        user_id: user.id
      })

      # Users.calculate_user_pref_table(user)
      _recipe_grade = Users.calculate_recipe_grading(recipe, user)
    end
  end

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
