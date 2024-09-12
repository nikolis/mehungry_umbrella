defmodule Mehungry.NutrientTest do
  use Mehungry.DataCase

  alias Mehungry.FdcFoodParser
  alias Mehungry.Food

  describe "Parsing the data" do
    test "parsing basic example" do
      FdcFoodParser.get_ingredients_from_food_data_central_json_file(
        "/home/nikolis/Documents/foundationDownload.json"
      )

      Food.search_ingredient("beans", nil)
    end
  end
end
