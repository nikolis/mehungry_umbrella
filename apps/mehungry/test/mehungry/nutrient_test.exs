defmodule Mehungry.NutrientTest do
  use Mehungry.DataCase

  alias Mehungry.FdcFoodParser
  alias Mehungry.Food

  setup_all do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Mehungry.Repo)
    # we are setting :auto here so that the data persists for all tests,
    # normally (with :shared mode) every process runs in a transaction
    # and rolls back when it exits. setup_all runs in a distinct process
    # from each test so the data doesn't exist for each test.
    Ecto.Adapters.SQL.Sandbox.mode(Mehungry.Repo, :auto)

    FdcFoodParser.get_ingredients_from_food_data_central_json_file("test/foundationDownload.json")
    :ok
  end

  describe "Parsing the data" do
    test "parsing basic example" do
      [ingredient | _rest] = Food.search_ingredient("beans", nil)
      [grammar] = Food.search_measurement_unit("grammar")
      user = Mehungry.AccountsFixtures.user_fixture()

      recipe =
        Mehungry.FoodFixtures.recipe_fixture(user, %{
          recipe_ingredients: [
            %{ingredient_id: ingredient.id, measurement_unit_id: grammar.id, quantity: 500}
          ]
        })

      recipe = Food.get_recipe!(recipe.id)
      {num, nutrients} = Mehungry.Food.RecipeUtils.get_nutrients(recipe)

      nutrients_changed =
        nutrients
        |> Enum.map(fn x -> Map.new([{x.name, x}]) end)
        |> Enum.reduce(&Map.merge/2)

      assert nutrients_changed == recipe.nutrients
      IO.inspect(Mehungry.Food.RecipeUtils.sort_nutrients_from_db(recipe.nutrients))
    end
  end
end
