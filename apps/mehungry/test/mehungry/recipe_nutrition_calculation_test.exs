defmodule Mehungry.RecipeNutritionCalculationTest do
  use Mehungry.DataCase

  alias Mehungry.FdcFoodParser
  alias Mehungry.Food
  alias Mehungry.Languages
  import Mehungry.{AccountsFixtures}

  @create_params_recipe %{servings: 3, title: "Title Recipe", language_name: "En"}

  defp create_user(_) do
    user = user_fixture()
    %{user: user}
  end

  describe "Parsing the data and calculting food nutrition" do
    setup [:create_user]

    test "parsing basic example", %{user: user} do
      {:ok, _lang} = Languages.create_language(%{name: "En"})

      FdcFoodParser.get_ingredients_from_food_data_central_json_file(
        "/home/nikolis/Documents/foundationDownload.json"
      )

      ingredient = Enum.at(Food.search_ingredient("beans", nil), 0)

      ingredient2 =
        Enum.at(Food.search_ingredient("Chicken, breast, boneless, skinless, raw", nil), 0)

      ingredient3 = Enum.at(Food.search_ingredient("beef", nil), 0)
      ingredient4 = Enum.at(Food.search_ingredient("chicken", nil), 0)

      ingredient5 = Enum.at(Food.search_ingredient("Broccoli", nil), 0)
      ingredient6 = Enum.at(Food.search_ingredient("oil", nil), 0)

      ingredient7 = Enum.at(Food.search_ingredient("cheese", nil), 0)
      ingredient8 = Enum.at(Food.search_ingredient("cheese", nil), 0)

      ingredients = [
        ingredient,
        ingredient2,
        ingredient3,
        ingredient4,
        ingredient5,
        ingredient6,
        ingredient7,
        ingredient8
      ]

      measurement_unit = Enum.at(Food.get_measurement_unit_by_name("grammar"), 0)

      ingredients =
        Enum.map(ingredients, fn x ->
          %{
            ingredient_id: x.id,
            measurement_unit_id: measurement_unit.id,
            quantity: Enum.random(0..800)
          }
        end)

      recipe_params =
        @create_params_recipe
        |> Enum.into(%{recipe_ingredients: ingredients})
        |> Enum.into(%{user_id: user.id})

      assert {:ok, %Mehungry.Food.Recipe{} = _recipe} = Food.create_recipe(recipe_params)
    end
  end
end
