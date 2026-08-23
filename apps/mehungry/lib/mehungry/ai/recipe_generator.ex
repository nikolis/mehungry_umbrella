defmodule Mehungry.AI.RecipeGenerator do
  @moduledoc """
  Two-phase AI recipe generation constrained to USDA/FDC ingredients in the database.

  Phase 1: extract ingredient names from user description.
  Phase 2: resolve each name to DB ingredient IDs + their available IngredientPortions.
  Phase 3: generate full recipe JSON using only the resolved IDs.
  """

  require Logger
  alias Mehungry.Food

  @model "claude-sonnet-4-6"

  # Words that indicate a partial/processed ingredient form.
  # When none of these appear in the search term but they appear in a candidate
  # name, that candidate is rejected so the ingredient falls to Phase 2b.
  @partial_indicators ~w(yolk white albumen powder dried dehydrated freeze extract concentrate)

  @doc """
  Full pipeline. Returns {:ok, attrs_map, unmatched_names} or {:error, reason}.
  attrs_map is ready to pass to Recipe.changeset/2 via init/3.

  Delegates to RecipeAgent (tool-use loop). Falls back to the legacy
  hardcoded pipeline if the agent returns an error.
  """
  def run(description) do
    case Mehungry.AI.Agents.RecipeAgent.run(description) do
      {:ok, attrs, unmatched} ->
        {:ok, attrs, unmatched}

      {:error, reason} ->
        Logger.warning("RecipeAgent failed (#{inspect(reason)}), falling back to legacy pipeline")
        run_legacy(description)
    end
  end

  defp run_legacy(description) do
    with {:ok, names} <- extract_ingredient_names(description),
         _ = Logger.info("Phase 1 extracted: #{inspect(names)}"),
         {resolved, unmatched} <- resolve_ingredients(names),
         _ =
           Logger.info(
             "Phase 2 resolved: #{inspect(Enum.map(resolved, & &1.searched_name))}, unmatched: #{inspect(unmatched)}"
           ),
         {resolved, still_unmatched} <- create_missing_ingredients(resolved, unmatched),
         {:ok, attrs} <- generate_recipe(description, resolved) do
      {:ok, validate_ingredients(attrs, resolved), still_unmatched}
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
    gram_unit =
      case Food.get_measurement_unit_by_name("gram") do
        [unit | _] -> unit
        _ -> nil
      end

    {resolved, unmatched} =
      names
      |> Enum.map(fn name -> {name, resolve_one(name, gram_unit)} end)
      |> Enum.split_with(fn {_name, matches} -> matches != [] end)

    resolved_ctx =
      Enum.map(resolved, fn {name, matches} ->
        %{searched_name: name, db_matches: matches}
      end)

    unmatched_names = Enum.map(unmatched, fn {name, _} -> name end)

    {resolved_ctx, unmatched_names}
  end

  defp resolve_one(name, gram_unit) do
    Food.IngredientSearch.search(name)
    |> rerank_by_name(name)
    |> filter_by_name_relevance(name)
    |> reject_partial_variants(name)
    |> Enum.take(5)
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

  # Require at least one word from the search term to closely match the
  # candidate's FIRST word. This prevents secondary-ingredient matches like
  # "Pasta homemade, made with egg, cooked" matching a search for "egg"
  # (first word "pasta" has near-zero similarity to "egg").
  # We check search-term words against the candidate's first word only, so
  # multi-word searches like "ground beef" still match "Beef, ground, 70% lean"
  # because "beef" (a search word) matches "beef" (the candidate's first word).
  defp filter_by_name_relevance(ingredients, search_term, threshold \\ 0.6) do
    search_words =
      search_term
      |> String.downcase()
      |> String.split(~r/[\s,]+/)
      |> Enum.reject(&(String.length(&1) == 0))

    Enum.filter(ingredients, fn ing ->
      candidate_first =
        ing.name
        |> String.downcase()
        |> String.split(~r/[\s,]+/)
        |> List.first("")

      Enum.any?(search_words, fn sw ->
        String.jaro_distance(sw, candidate_first) >= threshold
      end)
    end)
  end

  # Reject candidates that are partial/processed forms of an ingredient when
  # the original search term doesn't call for them.
  # e.g. searching "eggs" → rejects "Egg yolk" and "Egg white" so the
  # ingredient falls through to Phase 2b which creates a whole-egg entry.
  defp reject_partial_variants(ingredients, search_term) do
    search_lower = String.downcase(search_term)

    Enum.reject(ingredients, fn ing ->
      ing_lower = String.downcase(ing.name)

      Enum.any?(@partial_indicators, fn indicator ->
        String.contains?(ing_lower, indicator) and not String.contains?(search_lower, indicator)
      end)
    end)
  end

  # Re-rank DB search results so ingredients whose name *starts with* the
  # searched term come first. This prevents incidental matches like
  # "Fish herring eggs" ranking above "Eggs, whole, raw" when searching "eggs".
  defp rerank_by_name(results, search_term) do
    query_first_word =
      search_term
      |> String.downcase()
      |> String.split(~r/[\s,]+/)
      |> List.first("")

    Enum.sort_by(results, fn ing ->
      ing_first_word =
        ing.name
        |> String.downcase()
        |> String.split(~r/[\s,]+/)
        |> List.first("")

      # Negate so higher similarity floats to the top
      -String.jaro_distance(ing_first_word, query_first_word)
    end)
  end

  # --- Phase 2b: create missing ingredients via USDA FDC parser ---

  defp create_missing_ingredients(resolved, []), do: {resolved, []}

  defp create_missing_ingredients(resolved, unmatched) do
    Logger.info(
      "Phase 2b: creating #{length(unmatched)} missing ingredients: #{inspect(unmatched)}"
    )

    gram_unit =
      case Food.get_measurement_unit_by_name("gram") do
        [unit | _] -> unit
        _ -> nil
      end

    case generate_usda_ingredient_json(unmatched) do
      {:ok, json_string, ingredient_list} ->
        Logger.info(
          "Phase 2b: AI returned #{length(ingredient_list)} ingredient(s), inserting via the FDC food parser"
        )

        Mehungry.FoodData.Usda.FoodParser.get_ingredients_from_json_body(json_string)

        # Any names beyond what the AI returned go straight to still_unmatched
        extra_unmatched = Enum.drop(unmatched, length(ingredient_list))

        # Re-resolve by original search name — DB now has the new entries
        {new_resolved, failed} =
          unmatched
          |> Enum.take(length(ingredient_list))
          |> Enum.map(fn name ->
            matches = resolve_one(name, gram_unit)
            Logger.info("Phase 2b: re-resolved '#{name}' → #{length(matches)} match(es)")
            {name, matches}
          end)
          |> Enum.split_with(fn {_name, matches} -> matches != [] end)

        new_resolved_ctx =
          Enum.map(new_resolved, fn {name, matches} ->
            %{searched_name: name, db_matches: matches}
          end)

        failed_names = Enum.map(failed, fn {name, _} -> name end)

        {resolved ++ new_resolved_ctx, failed_names ++ extra_unmatched}

      {:error, reason} ->
        Logger.warning("Phase 2b: AI call failed: #{inspect(reason)}")
        {resolved, unmatched}
    end
  end

  defp generate_usda_ingredient_json(names) do
    system = """
    You are a USDA nutrition database assistant. Return ONLY a valid JSON array in USDA FDC SR Legacy format.
    No markdown, no explanation, no code fences — just the raw JSON array.
    """

    user = build_usda_ingredient_prompt(names)

    case call_api(system, user, 4096) do
      {:ok, text} ->
        clean =
          text
          |> String.trim()
          |> String.replace(~r/```json\s*/i, "")
          |> String.replace(~r/```\s*/, "")
          |> String.trim()

        case Jason.decode(clean) do
          {:ok, list} when is_list(list) -> {:ok, clean, list}
          other -> {:error, "Could not parse USDA ingredient JSON: #{inspect(other)}"}
        end

      error ->
        error
    end
  end

  defp build_usda_ingredient_prompt(names) do
    names_text = Enum.map_join(names, "\n", fn n -> "- #{n}" end)

    """
    Generate USDA FDC SR Legacy JSON entries for these ingredients:
    #{names_text}

    Return a JSON array with one object per ingredient in the SAME ORDER as the input list.
    Each object must follow this exact USDA FDC SR Legacy structure:

    {
      "description": "Ingredient name, USDA style (e.g. 'Eggs, whole, raw, fresh')",
      "foodClass": "FinalFood",
      "foodCategory": {"description": "Category name string (e.g. 'Dairy and Egg Products')"},
      "publicationDate": "4/1/2019",
      "nutrientConversionFactors": [],
      "foodPortions": [
        {
          "modifier": "unit name string (e.g. 'large', 'medium', 'cup', 'tablespoon', 'g')",
          "gramWeight": 50.0,
          "amount": 1.0,
          "value": 1.0,
          "id": 1,
          "sequenceNumber": 1
        }
      ],
      "foodNutrients": [
        {
          "amount": 12.56,
          "type": "FoodNutrient",
          "nutrient": {
            "id": 1003,
            "name": "Protein",
            "number": "203",
            "rank": 600,
            "unitName": "g"
          }
        }
      ]
    }

    Rules:
    - Use realistic USDA-style names for descriptions (e.g. "Eggs, whole, raw, fresh" not just "eggs").
    - foodCategory.description must be a plain category name string (no IDs).
    - foodPortions: always include "g" (gramWeight: 1.0) plus natural serving sizes for this food.
      For eggs/fruits/vegetables include: small (~38g), medium (~44g), large (~50g), extra-large (~56g), each (~50g).
      For liquids include: cup (~240g), tablespoon (~15g).
    - foodNutrients amounts are per 100g. Use realistic USDA values. Include at minimum:
        Protein (id:1003, unitName:"g"), Total lipid fat (id:1004, unitName:"g"),
        Carbohydrate (id:1005, unitName:"g"), Energy (id:1008, unitName:"kcal"),
        Sugars total (id:2000, unitName:"g"), Fiber (id:1079, unitName:"g"),
        Sodium (id:1093, unitName:"mg"), Calcium (id:1087, unitName:"mg").
    - id fields inside foodPortions and foodNutrients are sequential integers starting from 1 — no real USDA IDs needed.
    """
  end

  # --- Phase 3 ---

  defp generate_recipe(description, resolved_context) do
    system = """
    You are an expert chef and recipe writer with deep knowledge of global cuisines,
    culinary technique, and flavour balance. Generate complete recipes as valid JSON.

    CONSTRAINTS:
    - Use ONLY the ingredient_id and measurement_unit_id values listed in "Available Ingredients". Do NOT invent IDs.
    - For each searched ingredient, pick the DB candidate whose name most closely matches the plain ingredient (e.g. prefer "Garlic, raw" over "Garlic salt" when the recipe calls for garlic).
    - Prefer whole/raw/plain forms over processed, seasoned, or flavoured variants unless the recipe specifically requires them.
    - For measurement units, pick the most natural unit for that ingredient in this recipe (e.g. grams for solids, ml for liquids). Only use unit_ids listed under that ingredient's units.
    - If no candidate is a reasonable match for an ingredient, omit it entirely rather than substituting a wrong one.
    - Return ONLY valid JSON. No markdown, no explanation, no code fences.

    QUALITY STANDARDS:
    - description: 2-3 sentences of genuine culinary prose — evoke aroma, texture, and occasion. No hashtags here.
    - hashtags: 4-6 bare topic keywords (no # symbol) covering cuisine, main ingredient, dietary style, occasion.
    - steps: each step must state what to do, how long it takes, and sensory cues for doneness (colour, texture, smell). Write full paragraphs, not skeletons. Include an optional tip field for technique nuance.
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
      "description": "string — 2-3 sentences of culinary prose describing aroma, texture, and occasion. No hashtags here.",
      "hashtags": ["string"] — 4-6 bare topic keywords without # symbol, e.g. ["pasta","italian","vegetarian","dinner"],
      "servings": integer,
      "cooking_time_lower_limit": integer (minutes),
      "preperation_time_lower_limit": integer (minutes),
      "difficulty": integer (1=easy, 2=medium, 3=difficult),
      "steps": [{"description": "string — full paragraph with timing and sensory doneness cues", "tip": "optional technique tip string", "index": integer}],
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
        desc =
          case s["tip"] do
            tip when is_binary(tip) and tip != "" -> "#{s["description"]} — #{tip}"
            _ -> s["description"] || ""
          end

        %{"description" => desc, "index" => i}
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

    hashtag_str =
      case data["hashtags"] do
        tags when is_list(tags) and tags != [] ->
          " " <> Enum.map_join(tags, " ", &"##{&1}")

        _ ->
          ""
      end

    %{
      "title" => data["title"],
      "description" => "#{data["description"]}#{hashtag_str}",
      "servings" => data["servings"],
      "cooking_time_lower_limit" => data["cooking_time_lower_limit"],
      "preperation_time_lower_limit" => data["preperation_time_lower_limit"],
      "difficulty" => data["difficulty"],
      "steps" => steps,
      "recipe_ingredients" => recipe_ingredients
    }
  end

  # --- Phase 4: validate AI output against resolved DB context ---

  defp validate_ingredients(attrs, resolved) do
    # Build ingredient_id -> [unit_id] from what Phase 2 actually found in the DB
    valid_units_by_ingredient =
      resolved
      |> Enum.flat_map(fn %{db_matches: matches} -> matches end)
      |> Enum.reduce(%{}, fn m, acc ->
        unit_ids = Enum.map(m.units, & &1.unit_id)
        Map.put(acc, m.id, unit_ids)
      end)

    recipe_ingredients =
      (attrs["recipe_ingredients"] || [])
      |> Enum.map(fn ri ->
        ing_id = ri["ingredient_id"]
        unit_id = ri["measurement_unit_id"]

        case Map.get(valid_units_by_ingredient, ing_id) do
          nil ->
            # ingredient_id was hallucinated or not in our resolved set — drop it
            Logger.warning("AI returned unknown ingredient_id #{inspect(ing_id)}, dropping")
            nil

          [] ->
            nil

          valid_units ->
            if unit_id in valid_units do
              ri
            else
              # Unit was hallucinated or belongs to a different ingredient — use first valid one
              Logger.warning(
                "AI returned invalid unit_id #{inspect(unit_id)} for ingredient #{ing_id}, " <>
                  "replacing with #{inspect(List.first(valid_units))}"
              )

              %{ri | "measurement_unit_id" => List.first(valid_units)}
            end
        end
      end)
      |> Enum.reject(&is_nil/1)

    %{attrs | "recipe_ingredients" => recipe_ingredients}
  end

  # --- HTTP ---

  defp call_api(system, user, max_tokens \\ 2048) do
    case Mehungry.AI.Client.request(%{
           model: @model,
           system: system,
           messages: [%{role: "user", content: user}],
           max_tokens: max_tokens
         }) do
      {:ok, response} -> {:ok, Mehungry.AI.Client.text_from(response)}
      error -> error
    end
  end
end
