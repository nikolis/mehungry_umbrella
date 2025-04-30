defmodule MehungryWeb.Api.MealConverter do
  
  alias Mehungry.Food

  def convert(meal) do
    %{
      title: to_string(meal.name),
      steps: split_steps(meal.instructions),
      recipe_hashtags: meal.tags,
      user_id: 18,
      cooking_time_lower_limit: 0, 
      preperation_time_lower_limit: 0,
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
  end

  defp convert_ingredient(%{ingredient: name, measure: measure}) do
    {:ok, name} = PosTagger.rearrange_with_noun_first(name <>" \n")  

    ingredient = Food.search_ingredient(name ) |> find_best_match(:name)
    {quantity, unit_string} = parse_measure(measure)
    measurement_unit = search_measurement_unit(unit_string)

    %{
      ingredient_id: ingredient && ingredient.id,
      measurement_unit_id: measurement_unit && measurement_unit.id,
      quantity: quantity
    }
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
      {val, _} -> val
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

