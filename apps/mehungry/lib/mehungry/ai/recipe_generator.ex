defmodule Mehungry.AI.RecipeGenerator do
  @moduledoc """
  Two-phase AI recipe generation constrained to USDA/FDC ingredients in the database.

  Phase 1: extract ingredient names from user description.
  Phase 2: resolve each name to DB ingredient IDs + their available IngredientPortions.
  Phase 3: generate full recipe JSON using only the resolved IDs.
  """

  require Logger
  alias Mehungry.Food

  @api_url "https://api.anthropic.com/v1/messages"
  @model "claude-haiku-4-5-20251001"
  @timeout_ms 60_000

  @doc """
  Full pipeline. Returns {:ok, attrs_map, unmatched_names} or {:error, reason}.
  attrs_map is ready to pass to Recipe.changeset/2 via init/3.
  """
  def run(description) do
    with {:ok, names} <- extract_ingredient_names(description),
         {resolved, unmatched} <- resolve_ingredients(names),
         {:ok, attrs} <- generate_recipe(description, resolved) do
      {:ok, attrs, unmatched}
    end
  end

  # --- Phase 1 ---

  defp extract_ingredient_names(description) do
    system = """
    You extract ingredient names from recipe descriptions.
    Return ONLY a valid JSON array of simple English ingredient name strings.
    No quantities, no units, no preparation notes — just the ingredient names.
    Example: ["chicken breast", "garlic", "olive oil", "pasta"]
    """

    user = "Recipe description: #{description}"

    case call_api(system, user) do
      {:ok, text} ->
        text
        |> String.trim()
        |> extract_json_array()

      error ->
        error
    end
  end

  defp extract_json_array(text) do
    # Strip markdown code fences if the model wraps output
    clean =
      text
      |> String.replace(~r/```json\s*/i, "")
      |> String.replace(~r/```\s*/, "")
      |> String.trim()

    case Jason.decode(clean) do
      {:ok, names} when is_list(names) ->
        {:ok, Enum.filter(names, &is_binary/1)}

      _ ->
        {:error, "Could not parse ingredient list from AI response"}
    end
  end

  # --- Phase 2 ---

  defp resolve_ingredients(names) do
    gram_unit = case Food.get_measurement_unit_by_name("grammar") do
      [unit | _] -> unit
      _ -> nil
    end

    {resolved, unmatched} =
      names
      |> Enum.map(fn name -> {name, resolve_one(name, gram_unit)} end)
      |> Enum.split_with(fn {_name, matches} -> matches != [] end)

    resolved_ctx = Enum.map(resolved, fn {name, matches} ->
      %{searched_name: name, db_matches: matches}
    end)

    unmatched_names = Enum.map(unmatched, fn {name, _} -> name end)

    {resolved_ctx, unmatched_names}
  end

  defp resolve_one(name, gram_unit) do
    Food.search_ingredient_alt(name)
    |> Enum.take(3)
    |> Enum.map(fn ing ->
      portions = Food.get_measurement_unit_portions_for_ingredient(ing.id)

      units =
        portions
        |> Enum.filter(fn p -> p.measurement_unit != nil end)
        |> Enum.map(fn p ->
          %{
            unit_id: p.measurement_unit_id,
            unit_name: p.measurement_unit.name,
            gram_weight: p.gram_weight
          }
        end)

      units =
        if gram_unit != nil do
          gram_entry = %{unit_id: gram_unit.id, unit_name: "gram", gram_weight: 1.0}
          Enum.uniq_by(units ++ [gram_entry], & &1.unit_id)
        else
          units
        end

      %{id: ing.id, name: ing.name, units: units}
    end)
  end

  # --- Phase 3 ---

  defp generate_recipe(description, resolved_context) do
    system = """
    You are a recipe creator. Generate complete recipes as valid JSON.
    CONSTRAINT: Use ONLY the ingredient_id and measurement_unit_id values from the "Available Ingredients" section.
    Do NOT invent new IDs. If an ingredient has no suitable unit, skip it.
    Return ONLY valid JSON. No markdown, no explanation, no code fences.
    """

    user = build_generation_prompt(description, resolved_context)

    case call_api(system, user) do
      {:ok, text} ->
        text
        |> String.trim()
        |> String.replace(~r/```json\s*/i, "")
        |> String.replace(~r/```\s*/, "")
        |> String.trim()
        |> Jason.decode()
        |> case do
          {:ok, data} -> {:ok, normalize_attrs(data)}
          _ -> {:error, "Could not parse recipe JSON from AI response"}
        end

      error ->
        error
    end
  end

  defp build_generation_prompt(description, resolved_context) do
    ingredients_text =
      resolved_context
      |> Enum.map_join("\n", fn %{searched_name: name, db_matches: matches} ->
        matches_text =
          Enum.map_join(matches, " | ", fn m ->
            units_text =
              Enum.map_join(m.units, ", ", fn u ->
                "#{u.unit_name}(unit_id:#{u.unit_id},gram_weight:#{u.gram_weight})"
              end)

            "ingredient_id:#{m.id} \"#{m.name}\" units:[#{units_text}]"
          end)

        "- #{name}: #{matches_text}"
      end)

    """
    Recipe description: "#{description}"

    Available Ingredients (use ONLY these IDs):
    #{ingredients_text}

    Return JSON with this exact structure:
    {
      "title": "string",
      "description": "string (1-2 sentences)",
      "servings": integer,
      "cooking_time_lower_limit": integer (minutes),
      "preperation_time_lower_limit": integer (minutes),
      "difficulty": integer (1=easy, 2=medium, 3=difficult),
      "steps": [{"description": "string", "index": integer}],
      "recipe_ingredients": [{"ingredient_id": integer, "measurement_unit_id": integer, "quantity": float}]
    }

    Choose realistic quantities appropriate for the number of servings.
    Pick the most natural measurement unit for each ingredient from the available units.
    """
  end

  defp normalize_attrs(data) do
    steps =
      (data["steps"] || [])
      |> Enum.with_index()
      |> Enum.map(fn {s, i} ->
        %{"description" => s["description"] || "", "index" => i}
      end)

    recipe_ingredients =
      (data["recipe_ingredients"] || [])
      |> Enum.map(fn ri ->
        %{
          "ingredient_id" => ri["ingredient_id"],
          "measurement_unit_id" => ri["measurement_unit_id"],
          "quantity" => ri["quantity"]
        }
      end)
      |> Enum.reject(fn ri ->
        is_nil(ri["ingredient_id"]) or is_nil(ri["measurement_unit_id"])
      end)

    %{
      "title" => data["title"],
      "description" => data["description"],
      "servings" => data["servings"],
      "cooking_time_lower_limit" => data["cooking_time_lower_limit"],
      "preperation_time_lower_limit" => data["preperation_time_lower_limit"],
      "difficulty" => data["difficulty"],
      "steps" => steps,
      "recipe_ingredients" => recipe_ingredients
    }
  end

  # --- HTTP ---

  defp call_api(system, user) do
    api_key = Application.get_env(:mehungry, :anthropic_api_key, "")

    if api_key == "" do
      {:error, "ANTHROPIC_API_KEY is not configured"}
    else
      do_call_api(api_key, system, user)
    end
  end

  defp do_call_api(api_key, system, user) do
    body =
      Jason.encode!(%{
        model: @model,
        max_tokens: 2048,
        system: system,
        messages: [%{role: "user", content: user}]
      })

    headers = [
      {"Content-Type", "application/json"},
      {"x-api-key", api_key},
      {"anthropic-version", "2023-06-01"}
    ]

    case HTTPoison.post(@api_url, body, headers, recv_timeout: @timeout_ms) do
      {:ok, %HTTPoison.Response{status_code: 200, body: resp_body}} ->
        case Jason.decode(resp_body) do
          {:ok, %{"content" => [%{"text" => text} | _]}} ->
            {:ok, text}

          {:ok, response} ->
            Logger.warning("Unexpected Anthropic response shape: #{inspect(response)}")
            {:error, "Unexpected API response format"}
        end

      {:ok, %HTTPoison.Response{status_code: code, body: body}} ->
        Logger.warning("Anthropic API error #{code}: #{body}")
        {:error, "API returned status #{code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.warning("Anthropic HTTP error: #{inspect(reason)}")
        {:error, "HTTP request failed: #{inspect(reason)}"}
    end
  end
end
