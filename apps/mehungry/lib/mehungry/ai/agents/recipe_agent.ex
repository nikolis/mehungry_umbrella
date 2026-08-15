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

  # The unit vocabulary the agent picks from is the ingredient's `IngredientPortion`
  # rows, not bare measurement units — each portion is a real, human-meaningful
  # serving ("1 cup" = 240 g, "1 medium banana" = 118 g), including description-only
  # portions that have no measurement unit at all. Grams stay available as a
  # universal fallback under this reserved sentinel, so every ingredient always has
  # at least one selectable option even when it has no portions of its own.
  @grams_portion_id 0

  # Realism guardrails injected into every generation prompt. The overriding test
  # is: would this pass as something a real home cook of this cuisine actually
  # makes? Restraint beats novelty — these rules exist to suppress the invented,
  # "creative fusion" output an unconstrained model drifts toward.
  @culinary_rules """
  ## The one test that overrides everything

  Would a real home cook of this cuisine recognize this as a genuine dish they
  actually make? If not, it is wrong — no matter how "interesting" it sounds.
  You are not inventing a novel dish; you are writing down a real, plausible,
  edible one.

  ## Culinary rules

  - The cuisine is the top constraint. Every ingredient must belong to that
    cuisine's real pantry and appear in dishes cooks from there actually make.
  - Prefer familiar, traditional, widely recognizable combinations. Boring-but-real
    beats clever-but-invented, every time.
  - Every ingredient must earn its place with a clear culinary purpose. If you are
    unsure whether an ingredient belongs, omit it.
  - 5-12 primary ingredients is normal. Do not pad the list to seem sophisticated.
  - One main protein, unless the dish traditionally combines several. Never combine
    unrelated proteins.
  - Fruit only when it is a genuine part of the dish for that cuisine — not as a
    surprise "twist".
  - FUSION IS FORBIDDEN unless the request explicitly asks for a named fusion
    cuisine. Do not blend cuisines, and do not bolt one cuisine's signature
    ingredient onto another's dish.
  - Reject any justification that reduces to "adds complexity", "a unique flavor",
    "an unexpected twist", or "elevates the dish". Those are the tells of invented
    food. Cut it.
  """

  @doc """
  Generates a recipe from a natural-language description.

  `opts` may carry a persona voice and creative grounding so the recipe reads
  as authored by a character rather than a generic AI food writer:

    * `:persona` — an `%AI.Bot.Persona{}` (voice_prompt, uses_hashtags)
    * `:origin` — free-text place, e.g. "Rethymno -> Crete -> Greece"
    * `:story` — optional backstory
    * `:seed_ingredients` — `%{"primary" => [names], "spice" => [...], "avoid" => [...]}`

  With no persona the behavior is unchanged (generic expert-chef voice).

  Returns {:ok, attrs_map, []} or {:error, reason}.
  """
  def run(description, opts \\ []) do
    brief = build_brief(opts)
    context = %{gram_unit: fetch_gram_unit(), brief: brief}

    sys_prompt = system_prompt(brief)
    user_prompt = "Create a recipe from this description: #{description}"

    Logger.debug("""
    [RecipeAgent] Prompt for this run:
    ── SYSTEM ──────────────────────────────────────────────
    #{sys_prompt}
    ── USER ────────────────────────────────────────────────
    #{user_prompt}
    ────────────────────────────────────────────────────────
    """)

    case run_once(sys_prompt, user_prompt, context) do
      {:error, :no_submit} ->
        # A persona-heavy run can end in prose without ever calling submit_recipe.
        # Retry once with a firmer, unmissable instruction before giving up.
        Logger.warning(
          "[RecipeAgent] Run ended without submitting a recipe; retrying once with a firmer submit instruction"
        )

        firm_prompt =
          user_prompt <>
            "\n\nIMPORTANT: You MUST finish by calling the submit_recipe tool with the " <>
            "complete recipe. Do NOT reply with prose or a description of the recipe — " <>
            "the ONLY way to complete this task is to call submit_recipe."

        case run_once(sys_prompt, firm_prompt, context) do
          {:error, :no_submit} -> {:error, "Agent completed without submitting a recipe"}
          other -> other
        end

      other ->
        other
    end
  end

  # One agent pass. Returns the submitted `{:ok, attrs, unmatched}` (smuggled out
  # of the submit_recipe handler via the process dictionary), `{:error, :no_submit}`
  # when the loop ended without submitting, or the agent's own `{:error, reason}`.
  defp run_once(sys_prompt, user_prompt, context) do
    Process.put(__MODULE__, nil)
    Process.put({__MODULE__, :offered}, %{})

    result =
      Agent.run(
        sys_prompt,
        user_prompt,
        tool_defs(),
        &handle_tool/3,
        context,
        model: @model,
        max_tokens: 8192,
        # Authentic specialty cuisines (e.g. Japanese: mirin, panko, dashi, bonito…)
        # trigger several create_ingredient calls before the recipe can be submitted;
        # 10 iterations could be exhausted mid-resolution (:max_iterations_reached).
        max_iterations: 14
      )

    case result do
      {:ok, _text} ->
        case Process.get(__MODULE__) do
          nil -> {:error, :no_submit}
          saved -> saved
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ── brief ─────────────────────────────────────────────────────────────────────

  # Normalize run/2 opts into a bounded map the prompts consume. nil persona
  # means "no character" — the generic voice is used everywhere.
  defp build_brief(opts) do
    persona = Keyword.get(opts, :persona)
    seed = Keyword.get(opts, :seed_ingredients) || %{}

    %{
      persona: persona,
      persona_name: persona && persona.name,
      voice_prompt: persona && persona.voice_prompt,
      uses_hashtags: (persona && persona.uses_hashtags) || false,
      cuisine: blank_to_nil(Keyword.get(opts, :cuisine)),
      origin: blank_to_nil(Keyword.get(opts, :origin)),
      story: blank_to_nil(Keyword.get(opts, :story)),
      primary: seed_names(seed, "primary"),
      spice: seed_names(seed, "spice"),
      garnish: seed_names(seed, "garnish"),
      avoid: seed_names(seed, "avoid")
    }
  end

  defp seed_names(seed, role) do
    (Map.get(seed, role) || Map.get(seed, String.to_atom(role)) || [])
    |> Enum.reject(&(&1 in [nil, ""]))
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(str) when is_binary(str), do: String.trim(str) |> then(&if(&1 == "", do: nil, else: &1))
  defp blank_to_nil(other), do: other

  defp has_persona?(%{persona: p}) when not is_nil(p), do: true
  defp has_persona?(_), do: false

  # ── system prompt ─────────────────────────────────────────────────────────────

  defp system_prompt(brief) do
    """
    #{persona_block(brief)}
    #{cuisine_block(brief)}
    To generate a recipe from the user's description, follow these steps IN ORDER:

    1. First commit to ONE specific, real, traditional dish of the cuisine and name
       it in the title (e.g. Greek → "Fasolada", Sicilian → "Pasta alla Norma",
       Oaxacan → "Tlayuda"). Do not invent a novel dish or a "twist" on one.
    2. List only the ingredients that dish genuinely contains — nothing added to seem
       creative or sophisticated. Cross-check each against the cuisine's real pantry.
    3. For EACH ingredient, call search_ingredient — inspect the returned candidates
       carefully and pick the best match (prefer whole/raw/plain forms over processed
       or flavoured variants)
    4. If search_ingredient returns no results for an ingredient, call create_ingredient
       to add it, then use the IDs it returns
    5. Draft the recipe using ONLY ingredient_id and ingredient_portion_id values from
       your tool results — never invent or guess numeric IDs. Prefer a real portion
       ("1 cup", "1 medium onion") over grams (portion_id 0) whenever the ingredient
       offers one. For each recipe ingredient also include the `name` you searched
       for; its id is verified against that name, so a mismatched or made-up id will
       be rejected
    6. Call submit_recipe with the complete recipe to validate and save it
    7. If submit_recipe returns errors, fix ONLY the reported invalid IDs and resubmit
    #{ingredient_directive(brief)}
    #{@culinary_rules}
    ## Recipe writing standards

    **Description:** Write 2-3 plain, honest sentences about the dish — what it is,
    how it tastes, when it's eaten. Sound like a real cook describing their food, not
    a food-blog headline: no purple prose, no piled-up adjectives, no "elevate/twist/
    symphony of flavours". Do NOT include hashtags in the description field; put them
    in the separate `hashtags` array instead.

    **Steps:** Each step must:
    - State what to do and how long it takes (e.g. "Cook for 4–5 minutes until the
      onions are translucent and just starting to colour at the edges")
    - Note sensory cues (colour, sound, smell, texture) that tell the cook it's done
    - Be a natural paragraph, not a one-liner skeleton
    - Include an optional `tip` for technique nuance (e.g. "Don't crowd the pan or
      the mushrooms will steam instead of brown")
    #{hashtag_directive(brief)}
    submit_recipe is the ONLY way to finish — always call it when the recipe is ready.
    """
  end

  # The opening identity. With a persona it becomes the character's voice;
  # without one it keeps the original generic expert-chef framing.
  defp persona_block(brief) do
    if has_persona?(brief) do
      origin = if brief.origin, do: " You cook from #{brief.origin}.", else: ""
      story = if brief.story, do: " #{brief.story}", else: ""

      """
      You are #{brief.persona_name}. #{brief.voice_prompt}#{origin}#{story}

      Write this recipe entirely in your own voice — the title, the description, and
      every step should sound like you, not like a generic recipe website. Keep your
      quirks, your measures, and your way of speaking about food.
      """
    else
      """
      You are an expert chef and recipe writer with deep knowledge of global cuisines,
      culinary technique, and flavour balance.
      """
    end
  end

  # The cuisine is the single most important constraint — it is stated first and
  # loudest so every downstream choice (dish, ingredients, technique) descends from
  # it. Empty string when no cuisine was supplied (the description then carries
  # whatever direction it has).
  defp cuisine_block(%{cuisine: cuisine}) when is_binary(cuisine) and cuisine != "" do
    """
    THE CUISINE IS: #{cuisine}. This is the top constraint and overrides everything
    else. The dish, and every single ingredient, must be authentic to #{cuisine}
    cooking. Do not drift toward other cuisines and do not fuse #{cuisine} with
    anything else.
    """
  end

  defp cuisine_block(_), do: ""

  # Steers ingredient selection from the setup's seed ingredients, and hard-bans
  # the avoid list. Empty string when there are no seed ingredients.
  defp ingredient_directive(%{primary: [], spice: [], garnish: [], avoid: []}), do: ""

  defp ingredient_directive(brief) do
    parts =
      [
        list_line("Build the recipe around these ingredients", brief.primary),
        list_line("Season with", brief.spice),
        list_line("Finish/garnish with", brief.garnish),
        list_line("NEVER use any of these ingredients under any circumstance", brief.avoid)
      ]
      |> Enum.reject(&(&1 == ""))

    if parts == [] do
      ""
    else
      "\n## Ingredient guidance\n\n" <> Enum.join(parts, "\n") <> "\n"
    end
  end

  defp list_line(_label, []), do: ""
  defp list_line(label, names), do: "- #{label}: #{Enum.join(names, ", ")}."

  # A folksy persona (grandma, tavern) doesn't hashtag; only ask for them when
  # the persona opts in, or when there is no persona (legacy social behaviour).
  defp hashtag_directive(brief) do
    if has_persona?(brief) and not brief.uses_hashtags do
      "\n**Hashtags:** Leave the hashtags array empty — this voice does not use hashtags.\n"
    else
      """

      **Hashtags:** 4–6 short topic keywords as bare strings without the # symbol,
      e.g. ["pasta", "italian", "vegetarian", "comfort food"]. Cover cuisine, main
      ingredient, dietary style, and occasion.
      """
    end
  end

  # ── tool definitions ──────────────────────────────────────────────────────────

  defp tool_defs do
    [
      %{
        name: "search_ingredient",
        description:
          "Search the ingredient database by name. Returns up to 5 candidates with " <>
            "their database ingredient_id and available portions (portion_id, unit, " <>
            "gram_weight) — each portion is a real serving such as \"1 cup\" or \"1 " <>
            "medium banana\". portion_id 0 always means grams by weight. Call this for " <>
            "every ingredient before using it in the recipe.",
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
            "ingredient_id and its portions (portion_id, unit, gram_weight).",
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
            "ingredient_portion_ids are resolved. Returns success or a list of errors to fix.",
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
                  name: %{
                    type: "string",
                    description:
                      "The ingredient name you searched for (e.g. 'Pecorino Romano', " <>
                        "'black pepper'). Must describe the same ingredient the " <>
                        "ingredient_id resolves to — it is checked against the search result."
                  },
                  ingredient_id: %{type: "integer"},
                  ingredient_portion_id: %{
                    type: "integer",
                    description:
                      "A portion_id returned for this ingredient by search_ingredient/" <>
                        "create_ingredient. Use 0 for grams by weight. quantity is then " <>
                        "counted in that portion (e.g. portion \"1 cup\" with quantity 2 = 2 cups)."
                  },
                  quantity: %{type: "number"}
                },
                required: ["name", "ingredient_id", "ingredient_portion_id", "quantity"]
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
            portions: build_portions(portions, gram_unit) |> Enum.take(4)
          }
        end)
      end

    Enum.each(candidates, &remember_offered(&1.ingredient_id, &1.name))

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
            remember_offered(ing.id, ing.name)

            portions =
              Food.get_measurement_unit_portions_for_ingredients([ing.id])
              |> Map.get(ing.id, [])

            %{
              created: true,
              ingredient_id: ing.id,
              name: ing.name,
              portions: build_portions(portions, gram_unit)
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

  defp handle_tool("submit_recipe", recipe_input, %{gram_unit: gram_unit} = context) do
    offered = Process.get({__MODULE__, :offered}) || %{}
    errors = validate_recipe(recipe_input, offered)

    if errors == [] do
      polished_input = polish_prose(recipe_input, Map.get(context, :brief))
      attrs = normalize_attrs(polished_input, gram_unit && gram_unit.id)
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

  defp validate_recipe(input, offered) do
    (input["recipe_ingredients"] || [])
    |> Enum.flat_map(fn ri ->
      ing_id = ri["ingredient_id"]
      portion_id = ri["ingredient_portion_id"]
      name = ri["name"]

      cond do
        is_nil(ing_id) ->
          ["A recipe_ingredient is missing ingredient_id"]

        is_nil(portion_id) ->
          ["ingredient_id #{ing_id} is missing ingredient_portion_id"]

        true ->
          # Provenance first: an id the model never received from a tool result
          # (a hallucinated or cross-wired id) is the dominant failure mode, and
          # it slips past a pure existence check because the table has ~100k rows.
          case check_provenance(ing_id, name, offered) do
            [] -> check_ingredient_portion(ing_id, portion_id)
            errors -> errors
          end
      end
    end)
  end

  # A submitted portion must be either the grams sentinel (0) or a real
  # `IngredientPortion` that belongs to this ingredient — mirroring the portions
  # search_ingredient/create_ingredient handed the model.
  defp check_ingredient_portion(_ing_id, @grams_portion_id), do: []

  defp check_ingredient_portion(ing_id, portion_id) do
    case Food.get_ingredient(ing_id) do
      nil ->
        [
          "ingredient_id #{ing_id} does not exist. " <>
            "Use search_ingredient to find a valid ID."
        ]

      _ing ->
        valid_ids =
          Food.get_measurement_unit_portions_for_ingredient(ing_id)
          |> Enum.map(& &1.id)

        if portion_id in valid_ids do
          []
        else
          [
            "ingredient_portion_id #{portion_id} is invalid for ingredient_id #{ing_id}. " <>
              "Valid portion_ids: #{inspect(Enum.uniq([@grams_portion_id | valid_ids]))} " <>
              "(0 = grams)."
          ]
        end
    end
  end

  # ── provenance ────────────────────────────────────────────────────────────────

  # Binds each submitted ingredient_id back to what the model was actually handed
  # by search_ingredient/create_ingredient this run. The existence check above
  # can't catch a hallucinated id that happens to point at a real row (e.g. a
  # Branded "DOMINO'S Pizza" that search never returns) or two offered ids swapped
  # between ingredients — this does, and feeds the self-correction loop a fix.
  @doc false
  def check_provenance(ing_id, name, offered) do
    case Map.fetch(offered, ing_id) do
      :error ->
        [
          "ingredient_id #{ing_id}#{named(name)} was never returned by search_ingredient " <>
            "or create_ingredient. Only use ingredient_id values from your tool results — " <>
            "search for this ingredient first, then use the id it returns."
        ]

      {:ok, offered_name} ->
        if name_matches?(name, offered_name) do
          []
        else
          [
            "ingredient_id #{ing_id} is \"#{offered_name}\", not \"#{name}\". Use the " <>
              "ingredient_id that search_ingredient returned for \"#{name}\"."
          ]
        end
    end
  end

  defp named(name) when is_binary(name) and name != "", do: " (\"#{name}\")"
  defp named(_), do: ""

  # Lenient agreement between the name the model says it is submitting and the
  # candidate name we returned for that id. Kept loose (substring either way, or
  # a close word-level jaro) so legitimate variants ("pecorino" vs "Cheese,
  # pecorino romano") don't cause resubmit thrash, while gross mismatches
  # (pepper vs pecorino) are still rejected. A blank name can't be checked, so it
  # passes the name gate — the id-provenance gate above still applies.
  @doc false
  def name_matches?(name, _offered) when not is_binary(name) or name == "", do: true

  def name_matches?(submitted, offered_name) do
    sub = String.downcase(submitted)
    off = String.downcase(offered_name)

    String.contains?(off, sub) or String.contains?(sub, off) or
      Enum.any?(normalize_words(sub), fn sw ->
        Enum.any?(normalize_words(off), &(String.jaro_distance(sw, &1) >= 0.8))
      end)
  end

  defp normalize_words(text) do
    text |> String.split(~r/[\s,]+/) |> Enum.reject(&(&1 == ""))
  end

  # Records an id→name the agent has actually been shown, so submit_recipe can
  # verify every submitted ingredient_id came from a real tool result this run.
  defp remember_offered(id, name) do
    offered = Process.get({__MODULE__, :offered}) || %{}
    Process.put({__MODULE__, :offered}, Map.put(offered, id, name))
  end

  # ── prose polish ──────────────────────────────────────────────────────────────

  # With a persona, the final rewrite speaks in the character's voice instead of
  # the generic Instagram/Pinterest "food writer" voice that flattens everything.
  defp polish_system_prompt(brief, step_count) when is_map(brief) do
    if has_persona?(brief) do
      origin = if brief.origin, do: " You cook from #{brief.origin}.", else: ""
      story = if brief.story, do: " #{brief.story}", else: ""
      hashtags = persona_polish_hashtags(brief)

      """
      You are #{brief.persona_name}. #{brief.voice_prompt}#{origin}#{story}

      You receive a structurally complete but plainly-written draft of one of your own
      recipes and must return it rewritten entirely in YOUR voice — as if you wrote it.

      Rewrite ONLY these four fields: title, description, steps, hashtags.
      Every other field must be omitted — do not echo ingredient IDs, quantities, or servings.

      title — how YOU would name this dish. Natural, not clickbait. Avoid generic
      "Golden/Ultimate/Perfect" recipe-website adjectives unless that is genuinely your voice.

      description — 2-3 sentences in your voice: where it comes from, when you make it,
      why it matters to you. Do NOT include hashtags here.

      steps — keep EXACTLY #{step_count} steps in the same order. Each step in your voice,
      but still practical: what to do, rough timing, and a sensory doneness cue. Weave in
      your tips and asides naturally.

      #{hashtags}

      Return ONLY valid JSON, no markdown fences, no explanation:
      {"title":"...","description":"...","steps":[{"index":0,"description":"..."}],"hashtags":["..."]}
      """
    else
      generic_polish_system_prompt(step_count)
    end
  end

  defp polish_system_prompt(_brief, step_count), do: generic_polish_system_prompt(step_count)

  defp persona_polish_hashtags(%{uses_hashtags: true}),
    do:
      "hashtags — 4-6 bare keywords without # prefix covering cuisine, main ingredient, dietary style, occasion."

  defp persona_polish_hashtags(_),
    do: "hashtags — return an empty array []; this voice does not use hashtags."

  defp generic_polish_system_prompt(step_count) do
    """
    You are a clear, honest recipe writer for a food platform. You receive a
    structurally complete but plainly-written draft recipe and return a cleaner
    version — one that reads like a real cook wrote it, not marketing copy.

    Rewrite ONLY these four fields: title, description, steps, hashtags.
    Every other field must be omitted from your response — do not echo ingredient IDs, quantities, or servings.

    title — keep the dish recognizable and its real, traditional name; do not invent a
    fancier one or bolt on decorative adjectives (keep "Saffron Rice Pilaf", not
    "Golden Saffron Symphony").

    description — 2-3 plain, honest sentences: what the dish is, how it tastes, when
    it's eaten. Sound like a real cook describing their food — NO purple prose, no
    piled-up adjectives, none of "evoke/elevate/twist/symphony/a hug in a bowl".
    Do NOT include hashtags here; they go in the separate hashtags array.

    steps — keep EXACTLY #{step_count} steps in the same order.
    Each step must: state what to do, include timing ("cook for 3-4 minutes"), and one sensory doneness cue
    ("until the onions are soft and starting to colour at the edges"). Plain and practical, not flowery.

    hashtags — 4-6 bare keywords without # prefix covering cuisine, main ingredient, dietary style, occasion.

    Return ONLY valid JSON, no markdown fences, no explanation:
    {"title":"...","description":"...","steps":[{"index":0,"description":"..."}],"hashtags":["..."]}
    """
  end

  defp polish_prose(recipe_input, brief) do
    original_step_count = length(recipe_input["steps"] || [])
    system = polish_system_prompt(brief, original_step_count)

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

  defp normalize_attrs(data, gram_unit_id) do
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
      |> Enum.reject(&(is_nil(&1["ingredient_id"]) or is_nil(&1["ingredient_portion_id"])))
      |> Enum.map(fn ri ->
        base = %{
          "ingredient_id" => ri["ingredient_id"],
          "quantity" => ri["quantity"] || 1.0
        }

        # The grams sentinel resolves to the gram measurement unit (portion-less,
        # nutrition treats quantity as grams directly); every other portion_id is
        # persisted as the authoritative `ingredient_portion_id`.
        case ri["ingredient_portion_id"] do
          @grams_portion_id -> Map.put(base, "measurement_unit_id", gram_unit_id)
          portion_id -> Map.put(base, "ingredient_portion_id", portion_id)
        end
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

  defp build_portions(portions, gram_unit) when is_list(portions) do
    real =
      portions
      |> Enum.map(fn p ->
        %{
          portion_id: p.id,
          unit: Mehungry.Food.IngredientPortion.display_name(p),
          gram_weight: p.gram_weight
        }
      end)
      # Drop portions whose label is meaningless to a cook (e.g. USDA "RACC",
      # "Quantity not specified") — see IngredientPortion.meaningful_label?/1.
      |> Enum.filter(&Mehungry.Food.IngredientPortion.meaningful_label?(&1.unit))
      |> Enum.uniq_by(& &1.portion_id)

    if gram_unit do
      real ++ [%{portion_id: @grams_portion_id, unit: "gram", gram_weight: 1.0}]
    else
      real
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
