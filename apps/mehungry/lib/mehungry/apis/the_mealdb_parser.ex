defmodule Mehubgry.Apis.TheMealdbParser do
  @moduledoc """
  Fetches meal data from an API endpoint and parses it into structured Meal structs.
  """

  defmodule Meal do
    @moduledoc """
    Defines a struct to hold a meal and its details.
    """

    defstruct [
      :id,
      :name,
      :category,
      :area,
      :instructions,
      :thumbnail,
      :tags,
      :youtube,
      :ingredients
    ]
  end

  @doc """
  Fetches meal data from a given URL and parses it into a list of %Meal{} structs.
  """
  def fetch_and_parse(url) do
    with {:ok, %HTTPoison.Response{status_code: 200, body: body}} <- HTTPoison.get(url),
         {:ok, %{"meals" => meals}} <- Jason.decode(body) do
      Enum.map(meals, &parse_meal/1)
    else
      {:ok, %HTTPoison.Response{status_code: status}} ->
        {:error, "Unexpected HTTP status code: #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Parses a single meal JSON map into a %Meal{} struct.
  """
  defp parse_meal(raw) do
    %Meal{
      id: raw["idMeal"],
      name: raw["strMeal"],
      category: raw["strCategory"],
      area: raw["strArea"],
      instructions: raw["strInstructions"],
      thumbnail: raw["strMealThumb"],
      tags: parse_tags(raw["strTags"]),
      youtube: raw["strYoutube"],
      ingredients: parse_ingredients(raw)
    }
  end

  @doc """
  Parses the `strTags` string into a list of tags.
  """
  defp parse_tags(nil), do: []
  defp parse_tags(tags), do: String.split(tags, ",", trim: true)

  @doc """
  Collects and combines ingredients and measurements into a list of maps like:
  [%{ingredient: "Potatoes", measure: "500g"}, ...]
  """
  defp parse_ingredients(raw) do
    1..20
    |> Enum.map(fn i ->
      ingredient = Map.get(raw, "strIngredient#{i}") |> clean_string()
      measure = Map.get(raw, "strMeasure#{i}") |> clean_string()

      case ingredient do
        nil -> nil
        "" -> nil
        _ -> %{ingredient: ingredient, measure: measure}
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Cleans up a string by stripping whitespace and converting empty strings to nil.
  """
  defp clean_string(nil), do: nil

  defp clean_string(str) when is_binary(str) do
    str
    |> String.trim()
    |> case do
      "" -> nil
      cleaned -> cleaned
    end
  end
end
