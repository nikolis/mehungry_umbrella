defmodule Mehungry.AI.TaxonomyClassifier do
  @moduledoc """
  Single-shot AI classification of USDA ingredients into taxonomy leaves.
  Mirrors `Mehungry.AI.IngredientTranslator`: one JSON prompt via
  `AI.Client.request/1`, fence-strip + `Jason.decode`, remap names→ids and
  slugs→node_ids, dropping any leaf the model invented.
  """

  @behaviour Mehungry.AI.TaxonomyClassifierBehaviour

  require Logger

  @model "claude-sonnet-4-6"

  @impl Mehungry.AI.TaxonomyClassifierBehaviour
  def classify(ingredients, leaves) when is_list(ingredients) and is_list(leaves) do
    name_to_id = Map.new(ingredients, fn %{id: id, name: name} -> {name, id} end)
    slug_to_node_id = Map.new(leaves, fn %{id: id, slug: slug} -> {slug, id} end)

    system = system_prompt(leaves)
    user = "Classify these USDA ingredient names:\n#{Jason.encode!(Map.keys(name_to_id))}"

    case call_api(system, user) do
      {:ok, text} -> parse(text, name_to_id, slug_to_node_id)
      error -> error
    end
  end

  defp system_prompt(leaves) do
    leaf_list = Enum.map_join(leaves, "\n", fn %{slug: slug, path: path} -> "- #{slug}: #{path}" end)

    """
    You are a food taxonomist classifying ingredients for a recipe app.

    The ingredient names come from the USDA food database, which uses a specific
    technical naming convention: "Primary food, qualifier, qualifier, preparation
    method, fat trim level...". For example: "Beef, chuck, arm pot roast, separable
    lean only, cooked, braised" or "Oil, olive, salad or cooking". Focus on the CORE
    ingredient, not the qualifiers, when choosing a category.

    Assign each ingredient to exactly ONE of these leaf categories (identified by slug):

    #{leaf_list}

    When nothing fits, use "other-unclassified" with a low confidence.

    Return ONLY a valid JSON object mapping each original ingredient name to an object
    with the chosen leaf slug and a confidence between 0.0 and 1.0. No markdown, no
    explanation, no extra keys. Example:
    {
      "Beef, ground, 80% lean meat / 20% fat, cooked": {"leaf": "beef", "confidence": 0.95},
      "Oil, olive, salad or cooking": {"leaf": "vegetable-oils", "confidence": 0.9},
      "Some novelty product": {"leaf": "other-unclassified", "confidence": 0.2}
    }
    """
  end

  defp parse(text, name_to_id, slug_to_node_id) do
    cleaned =
      text
      |> String.trim()
      |> String.replace(~r/```json\s*/i, "")
      |> String.replace(~r/```\s*/, "")
      |> String.trim()

    case Jason.decode(cleaned) do
      {:ok, map} when is_map(map) ->
        rows = Enum.flat_map(map, &to_row(&1, name_to_id, slug_to_node_id))
        {:ok, rows}

      _ ->
        Logger.warning("TaxonomyClassifier: failed to parse response: #{inspect(text)}")
        {:error, "Could not parse classification response"}
    end
  end

  defp to_row({name, assignment}, name_to_id, slug_to_node_id) do
    with id when not is_nil(id) <- Map.get(name_to_id, name),
         slug when is_binary(slug) <- get_in_map(assignment, "leaf"),
         node_id when not is_nil(node_id) <- Map.get(slug_to_node_id, slug) do
      [%{ingredient_id: id, taxonomy_node_id: node_id, confidence: confidence(assignment)}]
    else
      _ -> []
    end
  end

  defp get_in_map(assignment, key) when is_map(assignment), do: Map.get(assignment, key)
  defp get_in_map(_, _), do: nil

  defp confidence(%{"confidence" => c}) when is_number(c), do: c * 1.0
  defp confidence(_), do: nil

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
