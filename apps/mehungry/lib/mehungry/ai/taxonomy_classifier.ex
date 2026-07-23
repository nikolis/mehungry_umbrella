defmodule Mehungry.AI.TaxonomyClassifier do
  @moduledoc """
  Classifies USDA ingredient names into the leaf nodes of an ingredient
  taxonomy. Single-shot JSON prompt over `Mehungry.AI.Client`, mirroring
  `Mehungry.AI.IngredientTranslator`.
  """

  @behaviour Mehungry.AI.TaxonomyClassifierBehaviour

  require Logger

  @model "claude-sonnet-4-6"
  @fallback_slug "other-unclassified"

  @impl true
  def classify(ingredients, leaves) when is_list(ingredients) and is_list(leaves) do
    name_to_id = Map.new(ingredients, fn %{id: id, name: name} -> {name, id} end)
    valid_slugs = MapSet.new(leaves, & &1.slug)

    system = system_prompt(leaves)

    user =
      "Classify these USDA ingredient names:\n#{Jason.encode!(Map.keys(name_to_id))}"

    case call_api(system, user) do
      {:ok, text} ->
        parse_classification_map(text, name_to_id, valid_slugs)

      error ->
        error
    end
  end

  defp system_prompt(leaves) do
    leaf_lines =
      Enum.map_join(leaves, "\n", fn %{slug: slug, path: path} -> "- #{slug}: #{path}" end)

    """
    You are a food scientist classifying ingredients from the USDA food database
    into a hierarchical food taxonomy.

    The ingredient names use the USDA naming convention: "Primary food, qualifier,
    qualifier, preparation method, fat trim level...". For example:
    "Chicken, broilers or fryers, breast, meat only, cooked, roasted" or
    "Oil, olive, salad or cooking". Identify the CORE ingredient and ignore
    qualifiers about fat trim, cooking method, and brand specifics.

    These are the available taxonomy leaves, given as "slug: full path":
    #{leaf_lines}

    Rules:
    - Assign each ingredient to exactly one leaf slug from the list above.
    - Choose the most specific leaf that fits the core ingredient.
    - Composite or prepared dishes belong under the prepared/composite leaves,
      not under their main ingredient.
    - If nothing fits, use "#{@fallback_slug}" with a low confidence.
    - Confidence is a number between 0.0 and 1.0 reflecting how certain you are.

    Return ONLY a valid JSON object mapping each original ingredient name to an
    object with "leaf" (a slug from the list) and "confidence".
    No markdown, no explanation, no extra keys.

    Example:
    {
      "Beef, ground, 80% lean meat / 20% fat, raw": {"leaf": "beef", "confidence": 0.98},
      "Fast food, pizza chain, 14\\" pizza": {"leaf": "fast-food", "confidence": 0.9}
    }
    """
  end

  defp parse_classification_map(text, name_to_id, valid_slugs) do
    cleaned =
      text
      |> String.trim()
      |> String.replace(~r/```json\s*/i, "")
      |> String.replace(~r/```\s*/, "")
      |> String.trim()

    case Jason.decode(cleaned) do
      {:ok, map} when is_map(map) ->
        result =
          map
          |> Enum.flat_map(fn {name, assignment} ->
            with id when not is_nil(id) <- Map.get(name_to_id, name),
                 %{"leaf" => slug} <- assignment,
                 true <- MapSet.member?(valid_slugs, slug) do
              confidence = normalize_confidence(assignment["confidence"])
              [{id, %{slug: slug, confidence: confidence}}]
            else
              _ ->
                Logger.warning(
                  "TaxonomyClassifier: dropping unusable assignment #{inspect(name)} => #{inspect(assignment)}"
                )

                []
            end
          end)
          |> Map.new()

        {:ok, result}

      _ ->
        Logger.warning("TaxonomyClassifier: failed to parse response: #{inspect(text)}")
        {:error, "Could not parse classification response"}
    end
  end

  defp normalize_confidence(confidence) when is_number(confidence) do
    confidence |> max(0.0) |> min(1.0) |> Kernel.*(1.0)
  end

  defp normalize_confidence(_), do: 0.0

  defp call_api(system, user) do
    case Mehungry.AI.Client.request(%{
           model: @model,
           system: system,
           messages: [%{role: "user", content: user}],
           max_tokens: 4096
         }) do
      {:ok, response} -> {:ok, Mehungry.AI.Client.text_from(response)}
      error -> error
    end
  end
end
