defmodule Mehungry.FdcFoodParserSurvey do
  @moduledoc """
  This module is responsible for parsing food and nutrition related data gotten from Food Data Central and translate them into a form that fits the database model goten from  https://www.usda.gov/
  """

  alias Mehungry.Food

  @measurement_unit_dict [
    {"grammar", "g"},
    {"gigatonne", "Gt"},
    {"milligram", "mg"},
    {"microgram", "µg"},
    {"nanogram", "ng"},
    {"picogram", "pg"},
    {"picogram", "pg"},
    {"kilocalorie", "kcal"},
    {"kilojoule", "kJ"},
    {"International Unit", "IU"},
    {"Specific gravity", "sp gr"}
  ]

  defp get_measurement_unit_foul_name(abbriviation) do
    result =
      Enum.filter(@measurement_unit_dict, fn {x, y} -> y == abbriviation or x == abbriviation end)

    case result do
      [] ->
        {abbriviation, abbriviation}

      [{name, abbriviation}] ->
        {name, abbriviation}

      _ ->
        {abbriviation, abbriviation}
    end
  end

  defp get_or_create_measurement_unit(measurement_unit_name) do
    result = Food.get_measurement_unit_by_name(measurement_unit_name)
    case result do
      [] ->
        {name, abbribiation} = get_measurement_unit_foul_name(measurement_unit_name)
        result = Food.get_measurement_unit_by_name(name)
        case result do
          [] -> 
            {:ok, measurement_unit} =
              Food.create_measurement_unit(%{name: name, alternate_name: abbribiation})
            IO.inspect(measurement_unit, label: "New measurement unit created with --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------")
            measurement_unit
          [measurement_unit, _] ->
            measurement_unit
        end

      [measurement_unit, _] ->
        measurement_unit

      [measurement_unit] ->
        measurement_unit
    end
  end

  def create_ingredient_nutrients(ingredient, nutrient, attrs) do
    attrs = %{
      ingredient_id: ingredient.id,
      nutrient_id: nutrient.id,
      amount:
        case attrs["amount"] do
          nil ->
            -1.0

          val ->
            val
        end,
      median: attrs["median"],
      data_points: attrs["dataPoints"],
      type_: attrs["type"]
    }

    Food.create_ingredient_nutrient(attrs)
  end

  defp get_or_create_nutrient(ingredient, origin_attrs) do
    nut_ing_attrs = origin_attrs
    origin_attrs = origin_attrs["nutrient"]
    measurement_unit = get_or_create_measurement_unit(origin_attrs["unitName"])

    attrs = %{
      reference_id: origin_attrs["id"],
      number: origin_attrs["number"],
      name: origin_attrs["name"],
      rank: origin_attrs["rank"],
      measurement_unit_id: measurement_unit.id
    }

    nutrient = Food.get_nutrient(attrs.name, attrs.measurement_unit_id)

    case nutrient do
      nil ->
        {:ok, nutrient} = Food.create_nutrient(attrs)
        create_ingredient_nutrients(ingredient, nutrient, nut_ing_attrs)

      nutr ->
        create_ingredient_nutrients(ingredient, nutr, nut_ing_attrs)
    end
  end

  defp create_ingredient_portions(food_portions, ingredient) do
    Enum.map(food_portions, fn x ->
      Food.create_measurement_unit(%{name: x["measureUnit"]["name"]})
      [measurement_unit | _rest] = Food.get_measurement_unit_by_name(x["measureUnit"]["name"])

      %{
        amount: x["amount"],
        value: x["value"],
        gram_weight: x["gramWeight"],
        reference_id: x["id"],
        min_year_acquired: x["minYearAcquired"],
        sequence_number: x["sequenceNumber"],
        ingredient_id: ingredient.id,
        measurement_unit_id: measurement_unit.id
      }
    end)
    |> Enum.each(fn b ->
      Food.create_ingredient_portion(b)
    end)
  end

  defp write_item_to_file(attrs) do
    {:ok, content} = File.read("leftovers.json")
    File.write("leftovers.json", content <>", \n" <> Poison.encode!(attrs), [:binary])
  end

  def create_ingredient(attrs) do
    if(is_nil(attrs["wweiaFoodCategory"]["wweiaFoodCategoryDescription"])) do
      IO.inspect("WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWRONGS")
      IO.inspect(attrs)
      IO.inspect(attrs["description"], label: "The ingredient being processed ")
      IO.inspect(attrs["wweiaFoodCategory"]["wweiaFoodCategoryDescription"], label: "The category")
      IO.inspect("------------------------------------------------------------------------")

      write_item_to_file(attrs)
    else
      IO.inspect("WORKING")
      IO.inspect(attrs["description"], label: "The ingredient being processed ")
      IO.inspect(attrs["wweiaFoodCategory"]["wweiaFoodCategoryDescription"], label: "The category")
      IO.inspect("------------------------------------------------------------------------")

      category = get_or_create_food_category(attrs["wweiaFoodCategory"]["wweiaFoodCategoryDescription"])

      food_portions = attrs["foodPortions"]
      food_nutrients = attrs["foodNutrients"]

      attrs = %{
        name: attrs["description"],
        food_class: attrs["foodClass"],
        nutrient_conversion_factors: attrs["nutrientConversionFactors"],
        publication_date: attrs["publicationDate"],
        category_id: category.id
      }

      case Food.create_ingredient(attrs) do
        {:ok, ingredient} ->
          Enum.map(food_nutrients, fn x ->
            {:ok, nutrient} = get_or_create_nutrient(ingredient, x)
            nutrient
          end)

          create_ingredient_portions(food_portions, ingredient)

        _ ->
          ""
      end
    end
  end

  defp get_or_create_food_category(category_name) do
    category = Food.search_category(category_name)
    if length(category) == 0 do
      {:ok, category} = Food.create_category(%{name: category_name})
      category
    else
      Enum.at(category, 0)
    end
  end

  def get_json(filename) do
    with {:ok, body} <- File.read(filename), {:ok, json} <- Poison.decode(body), do: {:ok, json}
  end

  def get_ingredients_from_food_data_central_json_file(file_path) do
    {:ok, json_body} = get_json(file_path)

    Enum.each(json_body["SurveyFoods"], fn x -> create_ingredient(x) end)
  end
end
