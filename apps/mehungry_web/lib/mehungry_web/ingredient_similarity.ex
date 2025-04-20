defmodule IngredientSimilarity do
  @moduledoc """
  Provides functions to calculate similarity between food ingredients
  based on nutritional, functional, and chemical traits.
  """

  @type vector :: [number()]
  @type ingredient :: %{
          name: String.t(),
          features: %{
            protein: float(),
            fat: float(),
            carbs: float(),
            water: float(),
            #melt_point: float(),
            #pH: float(),
            #function: MapSet.t(String.t())
          }
        }

  @doc "Computes cosine similarity between two numeric vectors"
  @spec cosine_similarity(vector(), vector()) :: float()
  def cosine_similarity(vec1, vec2) do
    dot = dot_product(vec1, vec2)
    mag1 = vector_magnitude(vec1)
    mag2 = vector_magnitude(vec2)

    if mag1 == 0 or mag2 == 0, do: 0.0, else: dot / (mag1 * mag2)
  end

  defp dot_product(a, b) do
    Enum.zip(a, b) |> Enum.reduce(0.0, fn {x, y}, acc -> acc + x * y end)
  end

  defp vector_magnitude(vec) do
    vec |> Enum.map(&(:math.pow(&1, 2))) |> Enum.sum() |> :math.sqrt()
  end

  @doc "Inverse of Euclidean distance (closer = more similar)"
  @spec euclidean_similarity(vector(), vector()) :: float()
  def euclidean_similarity(vec1, vec2) do
    distance =
      Enum.zip(vec1, vec2)
      |> Enum.map(fn {x, y} -> :math.pow(x - y, 2) end)
      |> Enum.sum()
      |> :math.sqrt()

    1.0 / (1.0 + distance)
  end

  @doc "Computes Jaccard similarity between two sets"
  @spec jaccard_similarity(MapSet.t(), MapSet.t()) :: float()
  def jaccard_similarity(set1, set2) do
    intersection = MapSet.intersection(set1, set2) |> MapSet.size()
    union = MapSet.union(set1, set2) |> MapSet.size()

    if union == 0, do: 1.0, else: intersection / union
  end

  @doc """
  Computes a composite similarity score between two ingredients.

  Weights:
  - 40% Nutritional (protein, fat, carbs, water)
  - 20% Functional (role in recipe)
  - 20% Melt Point
  - 20% pH
  """
  @spec ingredient_similarity(ingredient(), ingredient()) :: float()
  def ingredient_similarity(%{features: f1}, %{features: f2}) do
    nutrition1 = extract_nutrition(f1)
    nutrition2 = extract_nutrition(f2)

    nutrition_sim = cosine_similarity(nutrition1, nutrition2)
    melt_sim = euclidean_similarity([f1.melt_point], [f2.melt_point])
    pH_sim = euclidean_similarity([f1.pH], [f2.pH])
    function_sim = jaccard_similarity(f1.function, f2.function)

    0.4 * nutrition_sim +
      0.2 * function_sim +
      0.2 * melt_sim +
      0.2 * pH_sim
  end

  defp extract_nutrition(features) do
    [features.protein, features.fat, features.carbs, features.water]
  end
end

