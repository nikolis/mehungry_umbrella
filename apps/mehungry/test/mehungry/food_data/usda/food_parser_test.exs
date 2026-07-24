defmodule Mehungry.FoodData.Usda.FoodParserTest do
  use Mehungry.DataCase

  import Ecto.Query

  alias Mehungry.FoodData.Usda.FoodParser
  alias Mehungry.Food
  alias Mehungry.Food.{Ingredient, IngredientNutrient, IngredientPortion}
  alias Mehungry.Repo

  describe "get_ingredients_from_json_body/2 with a blank portion unit" do
    test "skips the portion instead of inventing a unit or rolling back the batch" do
      name = "Blank Unit Test Food #{System.unique_integer([:positive])}"

      body =
        Poison.encode!([
          %{
            "description" => name,
            "foodClass" => "FinalFood",
            "publicationDate" => "4/1/2019",
            "foodCategory" => %{"description" => "Legumes and Legume Products"},
            "nutrientConversionFactors" => [],
            "foodNutrients" => [],
            "foodPortions" => [
              %{
                "id" => 1,
                "amount" => 1.0,
                "gramWeight" => 30.0,
                "modifier" => "",
                "sequenceNumber" => 1
              }
            ]
          }
        ])

      assert {:ok, 1} = FoodParser.get_ingredients_from_json_body(body)

      ingredient = Food.get_ingredient_by_name(name)
      assert ingredient

      # The portion with no unit is skipped rather than stored (the parser never
      # invents a placeholder unit for a blank name).
      portions =
        Food.get_measurement_unit_portions_for_ingredients([ingredient.id])
        |> Map.get(ingredient.id, [])

      assert portions == []
    end
  end

  describe "get_ingredients_from_json_body/2 food_class" do
    test "stores the FDC dataType, not the always-\"FinalFood\" foodClass" do
      name = "DataType Test Food #{System.unique_integer([:positive])}"

      body =
        Poison.encode!([
          %{
            "description" => name,
            "dataType" => "Foundation",
            "foodClass" => "FinalFood",
            "publicationDate" => "4/1/2019",
            "foodCategory" => %{"description" => "Vegetables"},
            "nutrientConversionFactors" => [],
            "foodNutrients" => [],
            "foodPortions" => []
          }
        ])

      assert {:ok, 1} = FoodParser.get_ingredients_from_json_body(body)

      ingredient = Food.get_ingredient_by_name(name)
      assert ingredient.food_class == "Foundation"
    end

    test "falls back to foodClass when dataType is absent" do
      name = "No DataType Food #{System.unique_integer([:positive])}"

      body =
        Poison.encode!([
          %{
            "description" => name,
            "foodClass" => "FinalFood",
            "publicationDate" => "4/1/2019",
            "foodCategory" => %{"description" => "Vegetables"},
            "nutrientConversionFactors" => [],
            "foodNutrients" => [],
            "foodPortions" => []
          }
        ])

      assert {:ok, 1} = FoodParser.get_ingredients_from_json_body(body)
      assert Food.get_ingredient_by_name(name).food_class == "FinalFood"
    end
  end

  describe "get_ingredients_from_json_body/2 re-seeding an existing ingredient" do
    test "updates the row and replaces portions/nutrients instead of duplicating them" do
      name = "Re-seed Test Food #{System.unique_integer([:positive])}"

      body = fn publication_date ->
        Poison.encode!([
          %{
            "description" => name,
            "foodClass" => "FinalFood",
            "publicationDate" => publication_date,
            "foodCategory" => %{"description" => "Vegetables"},
            "nutrientConversionFactors" => [],
            "foodNutrients" => [
              %{
                "amount" => 5.0,
                "nutrient" => %{
                  "id" => 1003,
                  "number" => "203",
                  "name" => "Protein",
                  "rank" => 600,
                  "unitName" => "g"
                }
              }
            ],
            "foodPortions" => [
              %{
                "id" => 1,
                "amount" => 1.0,
                "gramWeight" => 240.0,
                "modifier" => "cup",
                "sequenceNumber" => 1
              }
            ]
          }
        ])
      end

      assert {:ok, 1} = FoodParser.get_ingredients_from_json_body(body.("4/1/2019"))
      assert {:ok, 1} = FoodParser.get_ingredients_from_json_body(body.("5/2/2020"))

      # A single ingredient row survives (updated by name, not duplicated).
      assert Repo.aggregate(from(i in Ingredient, where: i.name == ^name), :count) == 1

      ingredient = Food.get_ingredient_by_name(name)
      # Scalar fields reflect the second (latest) payload.
      assert ingredient.publication_date == "5/2/2020"

      # Portions and nutrient links are replaced, not appended, on the second seed.
      assert Repo.aggregate(
               from(p in IngredientPortion, where: p.ingredient_id == ^ingredient.id),
               :count
             ) == 1

      assert Repo.aggregate(
               from(n in IngredientNutrient, where: n.ingredient_id == ^ingredient.id),
               :count
             ) == 1
    end
  end

  describe "get_ingredients_from_json_body/2 with a raw FDC dataset wrapper" do
    test "unwraps a {\"FoundationFoods\" => [...]} object and populates fdc_id" do
      name = "Wrapper Fig #{System.unique_integer([:positive])}"

      body =
        Poison.encode!(%{
          "FoundationFoods" => [
            %{
              "description" => name,
              "dataType" => "Foundation",
              "foodClass" => "FinalFood",
              "fdcId" => 746_768,
              "publicationDate" => "4/1/2019",
              "foodCategory" => %{"description" => "Fruits and Fruit Juices"},
              "nutrientConversionFactors" => [],
              "foodNutrients" => [],
              "foodPortions" => []
            }
          ]
        })

      assert {:ok, 1} = FoodParser.get_ingredients_from_json_body(body)

      ingredient = Food.get_ingredient_by_name(name)
      assert ingredient.fdc_id == 746_768
      assert ingredient.data_type == "Foundation"
      assert ingredient.food_class == "Foundation"
    end

    test "backfills fdc_id when re-seeding a row first imported without one" do
      name = "Backfill Fig #{System.unique_integer([:positive])}"

      food = fn extra ->
        Map.merge(
          %{
            "description" => name,
            "foodClass" => "FinalFood",
            "publicationDate" => "1/1/2000",
            "foodCategory" => %{"description" => "Fruits"},
            "nutrientConversionFactors" => [],
            "foodNutrients" => [],
            "foodPortions" => []
          },
          extra
        )
      end

      # Old-style import: a bare array, no dataType/fdcId -> fdc_id stays nil.
      assert {:ok, 1} = FoodParser.get_ingredients_from_json_body(Poison.encode!([food.(%{})]))
      assert Food.get_ingredient_by_name(name).fdc_id == nil

      # Re-seed via the raw Foundation wrapper -> fdc_id is backfilled in place.
      wrapped =
        Poison.encode!(%{
          "FoundationFoods" => [food.(%{"dataType" => "Foundation", "fdcId" => 746_768})]
        })

      assert {:ok, 1} = FoodParser.get_ingredients_from_json_body(wrapped)

      ingredient = Food.get_ingredient_by_name(name)
      assert ingredient.fdc_id == 746_768
      assert ingredient.food_class == "Foundation"
    end

    test "still rejects a map with no known dataset keys" do
      assert {:error, :not_a_list} =
               FoodParser.get_ingredients_from_json_body(Poison.encode!(%{"nope" => []}))
    end
  end
end
