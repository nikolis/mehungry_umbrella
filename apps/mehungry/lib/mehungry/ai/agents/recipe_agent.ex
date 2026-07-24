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

  @model "claude-haiku-4-5-20251001"
  @writer_model "claude-sonnet-4-6"
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
        max_tokens: 8192,
        max_iterations: 10
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
                "2-3 sentences of culinary prose — aroma, texture, and occasion. " <>
                  "No hashtags here; put them in the hashtags array."
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
    top =
      Food.IngredientSearch.search(name)
      |> rerank_by_name(name)
      |> filter_by_name_relevance(name)
      |> reject_partial_variants(name)
      |> Enum.take(3)

    candidates =
      if top == [] do
        []
      else
        ids = Enum.map(top, & &1.id)
        portions_by_id = Food.get_measurement_unit_portions_for_ingredients(ids)

        Enum.map(top, fn ing ->
          portions = Map.get(portions_by_id, ing.id, [])

          %{
            ingredient_id: ing.id,
            name: ing.name,
            units: build_units(portions, gram_unit) |> Enum.take(3)
          }
        end)
      end

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

    {json_result, data_source} =
      case Mehungry.FoodData.Usda.FdcClient.lookup(name) do
        {:ok, json} ->
          Logger.info("RecipeAgent: found '#{name}' in USDA FDC database")
          {{:ok, json}, "usda_fdc"}

        {:error, reason} ->
          Logger.info(
            "RecipeAgent: USDA FDC lookup failed (#{inspect(reason)}), falling back to AI estimation"
          )

          {generate_usda_json_for(name), "ai_estimate"}
      end

    case json_result do
      {:ok, json_string} ->
        case Mehungry.FoodData.Usda.FoodParser.get_ingredients_from_json_body(
               json_string,
               data_source
             ) do
          {:ok, _count} ->
            :ok

          {:error, reason} ->
            Logger.warning(
              "RecipeAgent: ingredient insert for '#{name}' failed and was rolled back: #{inspect(reason)}"
            )
        end

        case Food.IngredientSearch.search(name)
             |> rerank_by_name(name)
             |> filter_by_name_relevance(name)
             |> Enum.take(1) do
          [ing | _] ->
            portions =
              Food.get_measurement_unit_portions_for_ingredients([ing.id])
              |> Map.get(ing.id, [])

            %{
              created: true,
              ingredient_id: ing.id,
              name: ing.name,
              units: build_units(portions, gram_unit)
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

  defp handle_tool("submit_recipe", recipe_input, %{gram_unit: gram_unit}) do
    errors = validate_recipe(recipe_input, gram_unit && gram_unit.id)

    if errors == [] do
      polished_input = polish_prose(recipe_input)
      attrs = normalize_attrs(polished_input)
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

  defp validate_recipe(input, gram_unit_id) do
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

  # ── prose polish ──────────────────────────────────────────────────────────────

  defp polish_prose(recipe_input) do
    original_step_count = length(recipe_input["steps"] || [])

    system = """
    You are a professional food writer for a recipe social media platform (Instagram, Pinterest).
    You receive a structurally complete but plainly-written draft recipe and must return a polished version.

    Rewrite ONLY these four fields: title, description, steps, hashtags.
    Every other field must be omitted from your response — do not echo ingredient IDs, quantities, or servings.

    title — keep the dish recognizable, make it enticing (e.g. "Golden Saffron Rice Pilaf" not "Saffron Rice")

    description — 2-3 sentences of genuine culinary prose. Evoke aroma, texture, and the occasion it suits.
    Do NOT include hashtags here; they go in the separate hashtags array.

    steps — keep EXACTLY #{original_step_count} steps in the same order.
    Each step must: state what to do, include timing ("cook for 3-4 minutes"), and one sensory doneness cue
    ("until the onions are soft and starting to colour at the edges"). Weave technique tips in naturally.

    hashtags — 4-6 bare keywords without # prefix covering cuisine, main ingredient, dietary style, occasion.

    Return ONLY valid JSON, no markdown fences, no explanation:
    {"title":"...","description":"...","steps":[{"index":0,"description":"..."}],"hashtags":["..."]}
    """

    user =
      Jason.encode!(%{
        title: recipe_input["title"],
        description: recipe_input["description"],
        steps: recipe_input["steps"] || [],
        hashtags: recipe_input["hashtags"] || []
      })

    case Client.request(%{
           model: @writer_model,
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
          {:ok, %{"title" => t, "description" => d, "steps" => s, "hashtags" => h}}
          when is_list(s) and is_list(h) ->
            polished_steps =
              s
              |> Enum.sort_by(&(Map.get(&1, "index") || Map.get(&1, :index) || 0))
              |> Enum.take(original_step_count)

            recipe_input
            |> Map.put("title", t)
            |> Map.put("description", d)
            |> Map.put("steps", polished_steps)
            |> Map.put("hashtags", h)

          _ ->
            Logger.warning("RecipeAgent: prose polish returned unexpected shape, using draft")
            recipe_input
        end

      {:error, reason} ->
        Logger.warning("RecipeAgent: prose polish failed (#{inspect(reason)}), using draft")
        recipe_input
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
    All nutrient amounts are per 100 g of the raw ingredient as consumed.
    Every amount field must be a realistic numeric value — do NOT use 0 unless
    the nutrient is genuinely absent in this ingredient.

    Each object must follow this exact structure (replace every VALUE with a
    realistic number based on your nutritional knowledge):

    {
      "description": "Ingredient, USDA style (e.g. 'Spinach, raw')",
      "foodClass": "FinalFood",
      "foodCategory": {"description": "Vegetables and Vegetable Products"},
      "publicationDate": "4/1/2019",
      "nutrientConversionFactors": [],
      "foodPortions": [
        {"modifier": "cup", "gramWeight": 30.0, "amount": 1.0, "value": 30.0, "id": 1, "sequenceNumber": 1},
        {"modifier": "tablespoon", "gramWeight": 4.0, "amount": 1.0, "value": 4.0, "id": 2, "sequenceNumber": 2}
      ],
      "foodNutrients": [
        {"amount": VALUE, "type": "FoodNutrient", "nutrient": {"id": 1008, "name": "Energy", "number": "208", "rank": 300, "unitName": "kcal"}},
        {"amount": VALUE, "type": "FoodNutrient", "nutrient": {"id": 1003, "name": "Protein", "number": "203", "rank": 600, "unitName": "g"}},
        {"amount": VALUE, "type": "FoodNutrient", "nutrient": {"id": 1004, "name": "Total lipid (fat)", "number": "204", "rank": 800, "unitName": "g"}},
        {"amount": VALUE, "type": "FoodNutrient", "nutrient": {"id": 1005, "name": "Carbohydrate, by difference", "number": "205", "rank": 1110, "unitName": "g"}},
        {"amount": VALUE, "type": "FoodNutrient", "nutrient": {"id": 1079, "name": "Fiber, total dietary", "number": "291", "rank": 1200, "unitName": "g"}},
        {"amount": VALUE, "type": "FoodNutrient", "nutrient": {"id": 1009, "name": "Starch", "number": "209", "rank": 1300, "unitName": "g"}},
        {"amount": VALUE, "type": "FoodNutrient", "nutrient": {"id": 2000, "name": "Sugars, total including NLEA", "number": "269", "rank": 1510, "unitName": "g"}},
        {"amount": VALUE, "type": "FoodNutrient", "nutrient": {"id": 1235, "name": "Added Sugars", "number": "539", "rank": 1540, "unitName": "g"}},
        {"amount": VALUE, "type": "FoodNutrient", "nutrient": {"id": 1012, "name": "Fructose", "number": "212", "rank": 1800, "unitName": "g"}},
        {"amount": VALUE, "type": "FoodNutrient", "nutrient": {"id": 1011, "name": "Glucose", "number": "211", "rank": 1700, "unitName": "g"}},
        {"amount": VALUE, "type": "FoodNutrient", "nutrient": {"id": 1015, "name": "Galactose", "number": "215", "rank": 2100, "unitName": "g"}},
        {"amount": VALUE, "type": "FoodNutrient", "nutrient": {"id": 1010, "name": "Sucrose", "number": "210", "rank": 1600, "unitName": "g"}},
        {"amount": VALUE, "type": "FoodNutrient", "nutrient": {"id": 1013, "name": "Lactose", "number": "213", "rank": 1900, "unitName": "g"}},
        {"amount": VALUE, "type": "FoodNutrient", "nutrient": {"id": 1014, "name": "Maltose", "number": "214", "rank": 2000, "unitName": "g"}},
        {"amount": VALUE, "type": "FoodNutrient", "nutrient": {"id": 1258, "name": "Fatty acids, total saturated", "number": "606", "rank": 9700, "unitName": "g"}},
        {"amount": VALUE, "type": "FoodNutrient", "nutrient": {"id": 1292, "name": "Fatty acids, total monounsaturated", "number": "645", "rank": 11400, "unitName": "g"}},
        {"amount": VALUE, "type": "FoodNutrient", "nutrient": {"id": 1293, "name": "Fatty acids, total polyunsaturated", "number": "646", "rank": 12900, "unitName": "g"}},
        {"amount": VALUE, "type": "FoodNutrient", "nutrient": {"id": 1253, "name": "Cholesterol", "number": "601", "rank": 15700, "unitName": "mg"}},
        {"amount": VALUE, "type": "FoodNutrient", "nutrient": {"id": 1087, "name": "Calcium, Ca", "number": "301", "rank": 5300, "unitName": "mg"}},
        {"amount": VALUE, "type": "FoodNutrient", "nutrient": {"id": 1089, "name": "Iron, Fe", "number": "303", "rank": 5400, "unitName": "mg"}},
        {"amount": VALUE, "type": "FoodNutrient", "nutrient": {"id": 1090, "name": "Magnesium, Mg", "number": "304", "rank": 5500, "unitName": "mg"}},
        {"amount": VALUE, "type": "FoodNutrient", "nutrient": {"id": 1091, "name": "Phosphorus, P", "number": "305", "rank": 5600, "unitName": "mg"}},
        {"amount": VALUE, "type": "FoodNutrient", "nutrient": {"id": 1092, "name": "Potassium, K", "number": "306", "rank": 5700, "unitName": "mg"}},
        {"amount": VALUE, "type": "FoodNutrient", "nutrient": {"id": 1093, "name": "Sodium, Na", "number": "307", "rank": 5800, "unitName": "mg"}},
        {"amount": VALUE, "type": "FoodNutrient", "nutrient": {"id": 1095, "name": "Zinc, Zn", "number": "309", "rank": 5900, "unitName": "mg"}},
        {"amount": VALUE, "type": "FoodNutrient", "nutrient": {"id": 1098, "name": "Copper, Cu", "number": "312", "rank": 6000, "unitName": "mg"}},
        {"amount": VALUE, "type": "FoodNutrient", "nutrient": {"id": 1101, "name": "Manganese, Mn", "number": "315", "rank": 6100, "unitName": "mg"}},
        {"amount": VALUE, "type": "FoodNutrient", "nutrient": {"id": 1103, "name": "Selenium, Se", "number": "317", "rank": 6200, "unitName": "µg"}},
        {"amount": VALUE, "type": "FoodNutrient", "nutrient": {"id": 1106, "name": "Vitamin A, RAE", "number": "320", "rank": 7300, "unitName": "µg"}},
        {"amount": VALUE, "type": "FoodNutrient", "nutrient": {"id": 1162, "name": "Vitamin C, total ascorbic acid", "number": "401", "rank": 6300, "unitName": "mg"}},
        {"amount": VALUE, "type": "FoodNutrient", "nutrient": {"id": 1114, "name": "Vitamin D (D2 + D3)", "number": "328", "rank": 8700, "unitName": "µg"}},
        {"amount": VALUE, "type": "FoodNutrient", "nutrient": {"id": 1109, "name": "Vitamin E (alpha-tocopherol)", "number": "323", "rank": 7900, "unitName": "mg"}},
        {"amount": VALUE, "type": "FoodNutrient", "nutrient": {"id": 1185, "name": "Vitamin K (phylloquinone)", "number": "430", "rank": 8800, "unitName": "µg"}},
        {"amount": VALUE, "type": "FoodNutrient", "nutrient": {"id": 1165, "name": "Thiamin", "number": "404", "rank": 6400, "unitName": "mg"}},
        {"amount": VALUE, "type": "FoodNutrient", "nutrient": {"id": 1166, "name": "Riboflavin", "number": "405", "rank": 6500, "unitName": "mg"}},
        {"amount": VALUE, "type": "FoodNutrient", "nutrient": {"id": 1167, "name": "Niacin", "number": "406", "rank": 6600, "unitName": "mg"}},
        {"amount": VALUE, "type": "FoodNutrient", "nutrient": {"id": 1175, "name": "Vitamin B-6", "number": "415", "rank": 6800, "unitName": "mg"}},
        {"amount": VALUE, "type": "FoodNutrient", "nutrient": {"id": 1177, "name": "Folate, total", "number": "417", "rank": 7100, "unitName": "µg"}},
        {"amount": VALUE, "type": "FoodNutrient", "nutrient": {"id": 1178, "name": "Vitamin B-12", "number": "418", "rank": 7400, "unitName": "µg"}},
        {"amount": VALUE, "type": "FoodNutrient", "nutrient": {"id": 1180, "name": "Choline, total", "number": "421", "rank": 7220, "unitName": "mg"}}
      ]
    }

    Include 2-3 natural serving sizes in foodPortions appropriate for this ingredient
    (e.g. cup/tablespoon/teaspoon for liquids and powders, piece/slice for whole foods).
    """
  end

  # ── ingredient search helpers ─────────────────────────────────────────────────

  defp fetch_gram_unit do
    case Food.get_measurement_unit_by_name("gram") do
      [unit | _] -> unit
      _ -> nil
    end
  end

  defp build_units(portions, gram_unit) when is_list(portions) do
    units =
      portions
      |> Enum.filter(& &1.measurement_unit)
      |> Enum.map(fn p ->
        %{
          unit_id: p.measurement_unit_id,
          unit_name: p.measurement_unit.name,
          gram_weight: p.gram_weight
        }
      end)

    if gram_unit do
      Enum.uniq_by(
        units ++ [%{unit_id: gram_unit.id, unit_name: "gram", gram_weight: 1.0}],
        & &1.unit_id
      )
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
      candidate_first =
        ing.name |> String.downcase() |> String.split(~r/[\s,]+/) |> List.first("")

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
