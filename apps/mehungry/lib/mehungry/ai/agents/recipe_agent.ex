defmodule Mehungry.AI.Agents.RecipeAgent do
  @moduledoc """
  Self-correcting recipe generation agent built on the AI.Agent tool-use loop.

  Replaces the hardcoded phase pipeline in RecipeGenerator. The AI drives
  ingredient resolution itself: it searches for each ingredient, creates any
  that are missing, and submits the final recipe through a validation tool.
  If the submission has invalid IDs the AI sees the errors and corrects them
  before resubmitting — no silent post-hoc patching.

  Returns the same {:ok, attrs, unmatched} tuple as RecipeGenerator.run/1.
  """

  require Logger
  alias Mehungry.{Food, AI.Agent, AI.Client}

  @model "claude-sonnet-4-6"
  @partial_indicators ~w(yolk white albumen powder dried dehydrated freeze extract concentrate)

  @doc """
  Generates a recipe from a natural-language description.
  Returns {:ok, attrs_map, []} or {:error, reason}.
  """
  def run(description) do
    Process.put(__MODULE__, nil)

    context = %{gram_unit: fetch_gram_unit()}

    result =
      Agent.run(
        system_prompt(),
        "Create a recipe from this description: #{description}",
        tool_defs(),
        &handle_tool/3,
        context,
        model: @model,
        max_tokens: 4096,
        max_iterations: 14
      )

    case result do
      {:ok, _text} ->
        case Process.get(__MODULE__) do
          nil -> {:error, "Agent completed without submitting a recipe"}
          saved -> saved
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ── system prompt ─────────────────────────────────────────────────────────────

  defp system_prompt do
    """
    You are an expert chef and recipe writer with deep knowledge of global cuisines,
    culinary technique, and flavour balance.

    To generate a recipe from the user's description, follow these steps IN ORDER:

    1. Identify all ingredients the recipe needs — think about the full flavour profile:
       aromatics, fats, acids, seasoning, and finishing touches
    2. For EACH ingredient, call search_ingredient — inspect the returned candidates
       carefully and pick the best match (prefer whole/raw/plain forms over processed
       or flavoured variants)
    3. If search_ingredient returns no results for an ingredient, call create_ingredient
       to add it, then use the IDs it returns
    4. Draft the recipe using ONLY ingredient_id and measurement_unit_id values from
       your tool results — never invent or guess numeric IDs
    5. Call submit_recipe with the complete recipe to validate and save it
    6. If submit_recipe returns errors, fix ONLY the reported invalid IDs and resubmit

    ## Recipe writing standards

    **Description:** Write 2-3 sentences of genuine culinary prose — evoke the aroma,
    texture, and occasion. Do NOT include hashtags in the description field; put them
    in the separate `hashtags` array instead.

    **Steps:** Each step must:
    - State what to do and how long it takes (e.g. "Cook for 4–5 minutes until the
      onions are translucent and just starting to colour at the edges")
    - Note sensory cues (colour, sound, smell, texture) that tell the cook it's done
    - Be a natural paragraph, not a one-liner skeleton
    - Include an optional `tip` for technique nuance (e.g. "Don't crowd the pan or
      the mushrooms will steam instead of brown")

    **Hashtags:** 4–6 short topic keywords as bare strings without the # symbol,
    e.g. ["pasta", "italian", "vegetarian", "comfort food"]. Cover cuisine, main
    ingredient, dietary style, and occasion.

    submit_recipe is the ONLY way to finish — always call it when the recipe is ready.
    """
  end

  # ── tool definitions ──────────────────────────────────────────────────────────

  defp tool_defs do
    [
      %{
        name: "search_ingredient",
        description:
          "Search the ingredient database by name. Returns up to 5 candidates with " <>
            "their database ingredient_id and available measurement units (unit_id, name, " <>
            "gram_weight). Call this for every ingredient before using it in the recipe.",
        input_schema: %{
          type: "object",
          properties: %{
            name: %{
              type: "string",
              description:
                "Plain English ingredient name, e.g. 'garlic', 'olive oil', 'chicken breast'"
            }
          },
          required: ["name"]
        }
      },
      %{
        name: "create_ingredient",
        description:
          "Add a new ingredient to the database when search_ingredient returns no results. " <>
            "Generates USDA-style nutritional data automatically. Returns the new " <>
            "ingredient_id and measurement units.",
        input_schema: %{
          type: "object",
          properties: %{
            name: %{
              type: "string",
              description: "Plain English ingredient name, e.g. 'saffron', 'tamarind paste'"
            }
          },
          required: ["name"]
        }
      },
      %{
        name: "submit_recipe",
        description:
          "Validate and save the completed recipe. Call once all ingredient_ids and " <>
            "measurement_unit_ids are resolved. Returns success or a list of errors to fix.",
        input_schema: %{
          type: "object",
          properties: %{
            title: %{type: "string"},
            description: %{
              type: "string",
              description:
                "1-2 sentence description followed by 4-6 SEO hashtags, " <>
                  "e.g. 'A hearty breakfast bowl. #breakfast #eggs #avocado #healthy'"
            },
            servings: %{type: "integer"},
            cooking_time_lower_limit: %{type: "integer", description: "Cooking time in minutes"},
            preperation_time_lower_limit: %{
              type: "integer",
              description: "Prep time in minutes"
            },
            difficulty: %{type: "integer", description: "1=easy, 2=medium, 3=hard"},
            steps: %{
              type: "array",
              items: %{
                type: "object",
                properties: %{
                  description: %{
                    type: "string",
                    description:
                      "Full step description including timing and sensory doneness cues"
                  },
                  index: %{type: "integer"},
                  tip: %{
                    type: "string",
                    description: "Optional short technique tip, e.g. 'Don't overcrowd the pan'"
                  }
                },
                required: ["description", "index"]
              }
            },
            hashtags: %{
              type: "array",
              items: %{type: "string"},
              description:
                "4-6 topic keywords without # prefix, e.g. [\"pasta\",\"italian\",\"dinner\"]"
            },
            recipe_ingredients: %{
              type: "array",
              items: %{
                type: "object",
                properties: %{
                  ingredient_id: %{type: "integer"},
                  measurement_unit_id: %{type: "integer"},
                  quantity: %{type: "number"}
                },
                required: ["ingredient_id", "measurement_unit_id", "quantity"]
              }
            }
          },
          required: ["title", "description", "servings", "steps", "recipe_ingredients"]
        }
      }
    ]
  end

  # ── tool handler ──────────────────────────────────────────────────────────────

  defp handle_tool("search_ingredient", %{"name" => name}, %{gram_unit: gram_unit}) do
    candidates =
      Food.search_ingredient_alt(name)
      |> rerank_by_name(name)
      |> filter_by_name_relevance(name)
      |> reject_partial_variants(name)
      |> Enum.take(5)
      |> Enum.map(fn ing ->
        %{ingredient_id: ing.id, name: ing.name, units: build_units(ing.id, gram_unit)}
      end)

    if candidates == [] do
      %{
        found: false,
        message: "No matches for '#{name}'. Call create_ingredient to add it."
      }
    else
      %{found: true, candidates: candidates}
    end
  end

  defp handle_tool("create_ingredient", %{"name" => name}, %{gram_unit: gram_unit}) do
    Logger.info("RecipeAgent: creating missing ingredient '#{name}'")

    case generate_usda_json_for(name) do
      {:ok, json_string} ->
        Mehungry.FdcFoodParserLeg.get_ingredients_from_json_body(json_string)

        case Food.search_ingredient_alt(name)
             |> rerank_by_name(name)
             |> filter_by_name_relevance(name)
             |> Enum.take(1) do
          [ing | _] ->
            %{
              created: true,
              ingredient_id: ing.id,
              name: ing.name,
              units: build_units(ing.id, gram_unit)
            }

          [] ->
            %{
              created: false,
              error:
                "Ingredient '#{name}' was inserted but could not be re-found. " <>
                  "Try a simpler, more generic name."
            }
        end

      {:error, reason} ->
        %{created: false, error: "Could not create ingredient: #{reason}"}
    end
  end

  defp handle_tool("submit_recipe", recipe_input, _ctx) do
    errors = validate_recipe(recipe_input)

    if errors == [] do
      attrs = normalize_attrs(recipe_input)
      Process.put(__MODULE__, {:ok, attrs, []})
      Logger.info("RecipeAgent: recipe '#{recipe_input["title"]}' submitted successfully")
      %{success: true, message: "Recipe '#{recipe_input["title"]}' saved."}
    else
      Logger.warning("RecipeAgent: submit_recipe errors: #{inspect(errors)}")
      %{success: false, errors: errors}
    end
  end

  defp handle_tool(name, _input, _ctx) do
    %{error: "Unknown tool: #{name}"}
  end

  # ── validation ────────────────────────────────────────────────────────────────

  defp validate_recipe(input) do
    gram_unit_id =
      case Food.get_measurement_unit_by_name("grammar") do
        [u | _] -> u.id
        _ -> nil
      end

    (input["recipe_ingredients"] || [])
    |> Enum.flat_map(fn ri ->
      ing_id = ri["ingredient_id"]
      unit_id = ri["measurement_unit_id"]

      cond do
        is_nil(ing_id) ->
          ["A recipe_ingredient is missing ingredient_id"]

        is_nil(unit_id) ->
          ["ingredient_id #{ing_id} is missing measurement_unit_id"]

        true ->
          check_ingredient_unit(ing_id, unit_id, gram_unit_id)
      end
    end)
  end

  defp check_ingredient_unit(ing_id, unit_id, gram_unit_id) do
    case Food.get_ingredient(ing_id) do
      nil ->
        [
          "ingredient_id #{ing_id} does not exist. " <>
            "Use search_ingredient to find a valid ID."
        ]

      _ing ->
        valid_ids =
          Food.get_measurement_unit_portions_for_ingredient(ing_id)
          |> Enum.filter(& &1.measurement_unit)
          |> Enum.map(& &1.measurement_unit_id)

        valid_ids = if gram_unit_id, do: [gram_unit_id | valid_ids], else: valid_ids

        if unit_id in valid_ids do
          []
        else
          [
            "measurement_unit_id #{unit_id} is invalid for ingredient_id #{ing_id}. " <>
              "Valid unit_ids: #{inspect(Enum.uniq(valid_ids))}"
          ]
        end
    end
  end

  # ── normalization ─────────────────────────────────────────────────────────────

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
      |> Enum.reject(&(is_nil(&1["ingredient_id"]) or is_nil(&1["measurement_unit_id"])))
      |> Enum.map(fn ri ->
        %{
          "ingredient_id" => ri["ingredient_id"],
          "measurement_unit_id" => ri["measurement_unit_id"],
          "quantity" => ri["quantity"] || 1.0
        }
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

  # ── USDA ingredient creation ──────────────────────────────────────────────────

  defp generate_usda_json_for(name) do
    system = """
    You are a USDA nutrition database assistant. Return ONLY a valid JSON array in
    USDA FDC SR Legacy format. No markdown, no explanation — just the raw JSON array.
    """

    user = usda_prompt([name])

    case Client.request(%{
           model: @model,
           system: system,
           messages: [%{role: "user", content: user}],
           max_tokens: 2048
         }) do
      {:ok, response} ->
        text =
          Client.text_from(response)
          |> String.trim()
          |> String.replace(~r/```json\s*/i, "")
          |> String.replace(~r/```\s*/, "")
          |> String.trim()

        case Jason.decode(text) do
          {:ok, [_ | _]} -> {:ok, text}
          other -> {:error, "Could not parse USDA JSON: #{inspect(other)}"}
        end

      error ->
        error
    end
  end

  defp usda_prompt(names) do
    names_text = Enum.map_join(names, "\n", &"- #{&1}")

    """
    Generate USDA FDC SR Legacy JSON entries for these ingredients:
    #{names_text}

    Return a JSON array with one object per ingredient in the SAME ORDER.
    Each object must follow this exact structure:

    {
      "description": "Ingredient name, USDA style (e.g. 'Eggs, whole, raw, fresh')",
      "foodClass": "FinalFood",
      "foodCategory": {"description": "Category name string"},
      "publicationDate": "4/1/2019",
      "nutrientConversionFactors": [],
      "foodPortions": [
        {"modifier": "g", "gramWeight": 1.0, "amount": 1.0, "value": 1.0, "id": 1, "sequenceNumber": 1}
      ],
      "foodNutrients": [
        {"amount": 0.0, "type": "FoodNutrient", "nutrient": {"id": 1003, "name": "Protein", "number": "203", "rank": 600, "unitName": "g"}},
        {"amount": 0.0, "type": "FoodNutrient", "nutrient": {"id": 1004, "name": "Total lipid (fat)", "number": "204", "rank": 800, "unitName": "g"}},
        {"amount": 0.0, "type": "FoodNutrient", "nutrient": {"id": 1005, "name": "Carbohydrate, by difference", "number": "205", "rank": 1110, "unitName": "g"}},
        {"amount": 0.0, "type": "FoodNutrient", "nutrient": {"id": 1008, "name": "Energy", "number": "208", "rank": 300, "unitName": "kcal"}}
      ]
    }

    Use realistic USDA-style names and realistic per-100g nutrient values.
    Include natural serving sizes in foodPortions (e.g. cup, tablespoon, piece).
    """
  end

  # ── ingredient search helpers ─────────────────────────────────────────────────

  defp fetch_gram_unit do
    case Food.get_measurement_unit_by_name("grammar") do
      [unit | _] -> unit
      _ -> nil
    end
  end

  defp build_units(ingredient_id, gram_unit) do
    units =
      Food.get_measurement_unit_portions_for_ingredient(ingredient_id)
      |> Enum.filter(& &1.measurement_unit)
      |> Enum.map(fn p ->
        %{
          unit_id: p.measurement_unit_id,
          unit_name: p.measurement_unit.name,
          gram_weight: p.gram_weight
        }
      end)

    if gram_unit do
      Enum.uniq_by(units ++ [%{unit_id: gram_unit.id, unit_name: "gram", gram_weight: 1.0}], & &1.unit_id)
    else
      units
    end
  end

  # Floats to top any candidate whose first word closely matches the search term,
  # preventing e.g. "Fish herring eggs" outranking "Eggs, whole, raw".
  defp rerank_by_name(results, search_term) do
    query_first = search_term |> String.downcase() |> String.split(~r/[\s,]+/) |> List.first("")

    Enum.sort_by(results, fn ing ->
      ing_first = ing.name |> String.downcase() |> String.split(~r/[\s,]+/) |> List.first("")
      -String.jaro_distance(ing_first, query_first)
    end)
  end

  # Requires at least one search word to closely match the candidate's first word,
  # filtering incidental secondary-ingredient matches.
  defp filter_by_name_relevance(ingredients, search_term, threshold \\ 0.6) do
    search_words =
      search_term |> String.downcase() |> String.split(~r/[\s,]+/) |> Enum.reject(&(&1 == ""))

    Enum.filter(ingredients, fn ing ->
      candidate_first = ing.name |> String.downcase() |> String.split(~r/[\s,]+/) |> List.first("")
      Enum.any?(search_words, &(String.jaro_distance(&1, candidate_first) >= threshold))
    end)
  end

  # Drops partial/processed forms (yolk, white, powder…) when the search term
  # doesn't ask for them, so e.g. "eggs" resolves to "Eggs, whole, raw".
  defp reject_partial_variants(ingredients, search_term) do
    search_lower = String.downcase(search_term)

    Enum.reject(ingredients, fn ing ->
      ing_lower = String.downcase(ing.name)

      Enum.any?(@partial_indicators, fn indicator ->
        String.contains?(ing_lower, indicator) and not String.contains?(search_lower, indicator)
      end)
    end)
  end
end
