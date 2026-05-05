defmodule MehungryWeb.Api.MealConverter do
  alias Mehungry.Food
  alias Mehungry.Repo
  require Logger

  def convert(meal) do
    %{
      title: to_string(meal.name),
      steps: split_steps(meal.instructions),
      recipe_hashtags: meal.tags,
      user_id: 18,
      description: meal.name <> Enum.reduce(meal.tags, "", fn x, y -> y <> " #" <> x end),
      cooking_time_lower_limit: 0,
      preperation_time_lower_limit: 0,
      servings: 0,
      difficulty: 0,
      language_name: "En",
      image_url: meal.image,
      detail_image_url: meal.youtube,
      recipe_ingredients: Enum.map(meal.ingredients, &convert_ingredient/1)
    }
  end

  defp split_steps(nil), do: []

  defp split_steps(instructions) do
    instructions
    |> String.split(~r/\.\s+|\r\n/, trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> map_strings_to_structs()
  end

  def map_strings_to_structs(strings) when is_list(strings) do
    Enum.with_index(strings, 1)
    |> Enum.map(fn {str, idx} ->
      %{
        title: str,
        description: str,
        index: idx
      }
    end)
  end

  defp convert_ingredient(%{ingredient: name, measure: measure}) do
    {:ok, name} = PosTagger.rearrange_with_noun_first(name <> " \n")

    ingredients =
      Food.search_ingredient_alt(name)
      |> Repo.preload([:measurement_unit, [ingredient_portions: :measurement_unit]])

    {quantity, unit_string} = parse_measure(measure)
    {ingredient_portion, _} = find_matching_ingredient(ingredients, unit_string)
    measurement_unit = search_measurement_unit(unit_string)

    Logger.info(
      "Converting ingredient with name: #{name} and the measurement unit is: #{measure}"
    )

    Logger.info("The measuremnet unit quantity: #{inspect(quantity)} ")
    Logger.info("The measuremnet unit : #{inspect(measurement_unit)} ")
    # Logger.info("The ingredient : #{inspect(ingredient_portion.ingredient_id)}")
    %{
      ingredient_id:
        case is_nil(ingredient_portion) do
          true ->
            nil

          false ->
            ingredient_portion.ingredient_id
        end,
      measurement_unit_id: measurement_unit && measurement_unit.id,
      quantity: quantity
    }
  end

  defp find_matching_ingredient(ingredients, mu_name) do
    ingredients =
      Enum.map(ingredients, fn x -> x.ingredient_portions end)
      |> List.flatten()
      |> Enum.map(fn x -> {x, x.measurement_unit.name} end)

    case ingredients do
      [] ->
        {nil, nil}

      [sthing] ->
        sthing

      [head | _tail] ->
        head
    end
  end

  defp parse_measure(nil), do: {nil, nil}

  defp parse_measure(measure) do
    case Regex.run(~r/([\d\/\.]+)?\s*(.+)?/, measure, capture: :all_but_first) do
      [num, unit] -> {parse_quantity(num), String.trim(unit || "")}
      _ -> {nil, String.trim(measure)}
    end
  end

  defp parse_quantity(nil), do: nil
  defp parse_quantity(""), do: nil

  defp parse_quantity(q) do
    # Handle fractions like "1/2"
    case Float.parse(q) do
      {val, _} ->
        val

      :error ->
        case String.split(q, "/") do
          [num, denom] -> String.to_float(num) / String.to_float(denom)
          _ -> nil
        end
    end
  end

  defp search_measurement_unit(""), do: nil

  defp search_measurement_unit(unit) do
    # If short like "tsp", use partial match
    if String.length(unit) <= 4 do
      Food.search_measurement_unit("#{unit}%") |> find_best_match(:name)
    else
      Food.search_measurement_unit(unit) |> find_best_match(:name)
    end
  end

  defp find_best_match(nil, _field), do: nil
  defp find_best_match([], _field), do: nil
  defp find_best_match([match], _field), do: match
  defp find_best_match([match | _], _field), do: match
end
