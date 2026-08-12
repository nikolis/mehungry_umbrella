defmodule Mehungry.NutrientTest do
  use Mehungry.DataCase

  alias Mehungry.FoodData.Usda.SeedFileParser
  alias Mehungry.Food

  setup_all do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Mehungry.Repo)
    # we are setting :auto here so that the data persists for all tests,
    # normally (with :shared mode) every process runs in a transaction
    # and rolls back when it exits. setup_all runs in a distinct process
    # from each test so the data doesn't exist for each test.
    Ecto.Adapters.SQL.Sandbox.mode(Mehungry.Repo, :auto)

    SeedFileParser.get_ingredients_from_food_data_central_json_file(
      "test/foundationDownload.json"
    )

    :ok
  end

  describe "Parsing the data" do
    test "parsing basic example" do
      [ingredient | _rest] = Food.search_ingredient("beans", nil)
      [gram] = Food.search_measurement_unit("gram")
      user = Mehungry.AccountsFixtures.user_fixture()

      recipe =
        Mehungry.FoodFixtures.recipe_fixture(user, %{
          recipe_ingredients: [
            %{ingredient_id: ingredient.id, measurement_unit_id: gram.id, quantity: 500}
          ]
        })

      recipe = Food.get_recipe!(recipe.id)

      # Mirrors the production call in RecipePutNutrientsWorker, which passes a
      # plain map (calculate_recipe_nutrition_value indexes with map[key], so a
      # bare %Recipe{} struct — which doesn't implement Access — would fail).
      {primary_size, nutrients} =
        Mehungry.Food.NutrientCalculation.calculate_recipe_nutrition_value(
          Map.from_struct(recipe)
        )

      names = MapSet.new(nutrients, & &1.name)

      assert primary_size == 8
      assert MapSet.size(names) > 0
      assert MapSet.member?(names, "Protein")
      assert MapSet.member?(names, "Carbohydrates")
    end
  end
end
