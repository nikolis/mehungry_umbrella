defmodule MehungryWeb.Api.TheMealDBParser do
  @moduledoc """
  Parses MealDB-style JSON into structured Elixir data.
  """
  def parse(json) do
    with {:ok, %{"meals" => [meal_data | _]}} <- Jason.decode(json) do
      meal = %{
        id: meal_data["idMeal"],
        name: meal_data["strMeal"],
        category: meal_data["strCategory"],
        area: meal_data["strArea"],
        instructions: meal_data["strInstructions"],
        tags: parse_tags(meal_data["strTags"]),
        image: meal_data["strMealThumb"],
        youtube: meal_data["strYoutube"],
        ingredients: parse_ingredients(meal_data),
        source: meal_data["strSource"]
      }

      {:ok, meal}
    else
      error -> {:error, error}
    end
  end

  defp parse_tags(nil), do: []
  defp parse_tags(tags_string), do: String.split(tags_string, ",")

  defp parse_ingredients(meal_data) do
    1..20
    |> Enum.map(fn i ->
      ingredient = Map.get(meal_data, "strIngredient#{i}")
      measure = Map.get(meal_data, "strMeasure#{i}")

      IO.inspect(ingredient,
        label: "--------------------------------------"
      )

      IO.inspect(measure,
        label: "--------------------------------------"
      )

      if is_binary(ingredient) and ingredient != "" do
        %{
          ingredient: ingredient,
          measure: measure || ""
        }
      else
        nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end
end

defmodule MehungryWeb.Api.MealFetcher do
  @moduledoc "Fetches and parses meal data from TheMealDB API"

  @endpoint "https://www.themealdb.com/api/json/v1/1/search.php?s=Arrabiata"

  def fetch_and_parse(url \\ @endpoint) do
    case HTTPoison.get(url) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, meal} = MehungryWeb.Api.TheMealDBParser.parse(body)

      {:ok, %HTTPoison.Response{status_code: code}} ->
        {:error, "Request failed with status code #{code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "HTTP error: #{inspect(reason)}"}
    end
  end
end
