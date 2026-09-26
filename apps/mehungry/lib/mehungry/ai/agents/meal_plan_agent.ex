defmodule Mehungry.AI.Agents.MealPlanAgent do
  @moduledoc """
  History-aware meal plan generation agent built on the AI.Agent tool-use loop.

  Replaces the single-shot prompt in MealPlanGenerator with a loop that:
    1. Reads the user's recent meal history to avoid repetition
    2. Queries the recipe catalog by keyword / slot type
    3. Optionally searches whole-food ingredients (fruit, nuts, cheese, yogurt)
       for snack slots and light sides
    4. Submits the complete 5-slot × 7-day plan for validation before creating
       records

  Each day has five slots (Breakfast, Morning Snack, Lunch, Afternoon Snack,
  Dinner). A slot may be filled by a **recipe** or by a single whole-food
  **ingredient** — snacks are typically an ingredient.

  If submit_plan returns errors (invalid recipe_id/ingredient_id, duplicate slot,
  out-of-range date) the AI corrects and resubmits automatically.

  Returns `{:ok, entries}` — a list of normalized, calendar-independent plan
  entries (see `normalize_entry/2`) — or `{:error, reason}`. The agent no longer
  persists anything itself: the caller decides whether to drop the entries onto
  the calendar (`MealPlanGenerator.persist_entries_to_calendar/3`) or store them
  as an independent blueprint plan (`MealBlueprints.store_plan_meals/2`).
  """

  require Logger
  alias Mehungry.{History, Food, AI.Agent, Search.RecipeVectorSearch}
  alias Mehungry.Food.IngredientPortion

  @model "claude-haiku-4-5-20251001"
  @history_days 21

  # The 5 calendar slots, in the label form the model emits and MealType.from_slot/1
  # maps back to canonical values.
  @slots ["Breakfast", "Morning Snack", "Lunch", "Afternoon Snack", "Dinner"]

  @doc """
  Generates and persists a 7-day meal plan for `user_id` starting at `start_date`.

  - `preferences` — free-text dietary preferences / blueprint brief
  - `recipes`     — list of recipe structs already loaded in the LiveView (unused;
    the agent searches the catalog itself)
  - `start_date`  — %Date{} for the first day of the plan
  - `user_id`     — integer
  - `blueprint`   — optional `%Mehungry.MealBlueprints.Blueprint{}` (or nil). Its
    targets reach the agent through `preferences` (see
    `MealBlueprints.blueprint_preferences/1`); the struct itself is currently
    unused here.

  Returns {:ok, [%UserMeal{}], skipped_count} or {:error, reason}.
  """
  def run(preferences, _recipes, start_date, user_id, _blueprint \\ nil) do
    # `offered`/`offered_ingredients` accumulate every id the search tools handed
    # the model this run; submit_plan rejects any id it never surfaced
    # (provenance). The validated result lands in `submitted` — no process-global
    # state.
    acc = %{
      user_id: user_id,
      start_date: start_date,
      offered: MapSet.new(),
      offered_ingredients: MapSet.new(),
      submitted: nil
    }

    result =
      Agent.run(
        system_prompt(preferences, start_date),
        initial_message(preferences, start_date),
        tool_defs(),
        &handle_tool/3,
        acc,
        telemetry_metadata: %{agent: "meal_plan"},
        model: @model,
        max_tokens: 4096,
        max_iterations: 14
      )

    case result do
      {:ok, _text, %{submitted: nil}} -> {:error, "Agent completed without submitting a plan"}
      {:ok, _text, %{submitted: entries}} -> {:ok, entries}
      {:error, reason} -> {:error, reason}
    end
  end

  # ── system prompt ─────────────────────────────────────────────────────────────

  defp system_prompt(preferences, start_date) do
    end_date = Date.add(start_date, 6)

    """
    You are a personal meal planner creating a 7-day plan.

    Plan period: #{Date.to_string(start_date)} to #{Date.to_string(end_date)} (inclusive).
    Meal slots each day: Breakfast, Morning Snack, Lunch, Afternoon Snack, Dinner (35 total entries).
    User preferences: #{preferences}

    WORKFLOW:
    1. Call get_recent_meals to see what the user has eaten lately — avoid heavy repetition
    2. Call search_catalog to find recipes suitable for each main slot:
       - Breakfast: light, quick meals
       - Lunch: moderate meals
       - Dinner: hearty, more complex meals
       You may call search_catalog multiple times with different queries
    3. For the two snack slots (and light sides), prefer a single whole-food
       INGREDIENT — fruit, nuts, cheese, yogurt, etc. Call search_ingredients to
       find them. Snacks do not need to be recipes.
    4. Draft the 35-entry plan using ONLY ids returned by the search tools
    5. Call submit_plan with the complete plan
    6. If submit_plan returns errors, fix the reported issues and resubmit

    RULES:
    - Each entry is EITHER a recipe (recipe_id + cooking_portions) OR an
      ingredient (ingredient_id + quantity, optional unit_selection) — never both
    - Use ONLY recipe_ids returned by search_catalog and ingredient_ids returned
      by search_ingredients — never invent IDs
    - Snacks should almost always be a single ingredient
    - Vary choices across the week — no recipe should appear more than twice
    - cooking_portions: 1–4 based on recipe servings
    - For ingredients, pick a unit_selection from the options search_ingredients
      returned and a sensible quantity (e.g. 1 apple, 30 g of nuts)
    - Use exact date strings in YYYY-MM-DD format
    - Slot values must be exactly one of: #{Enum.join(@slots, ", ")}
    - submit_plan is the ONLY way to complete the task
    """
  end

  defp initial_message(preferences, start_date) do
    "Create a 7-day, 5-slot-per-day meal plan starting #{Date.to_string(start_date)} " <>
      "with these preferences: #{preferences}"
  end

  # ── tool definitions ──────────────────────────────────────────────────────────

  defp tool_defs do
    [
      %{
        name: "get_recent_meals",
        description:
          "Returns the user's meal history for the past #{@history_days} days. " <>
            "Use this first to understand what has been eaten recently and avoid repetition.",
        input_schema: %{
          type: "object",
          properties: %{},
          required: []
        }
      },
      %{
        name: "search_catalog",
        description:
          "Semantically search the available recipe catalog by natural language query. " <>
            "Returns matching recipes with their recipe_id, title, difficulty (1–3), and servings. " <>
            "Use descriptive phrases like 'light high-protein breakfast', " <>
            "'quick vegetarian lunch', or 'hearty Mediterranean dinner'. " <>
            "Call with different queries to find recipes for each meal slot type.",
        input_schema: %{
          type: "object",
          properties: %{
            query: %{
              type: "string",
              description:
                "Natural language query, e.g. 'light high-protein breakfast', 'quick vegetarian lunch', 'hearty Mediterranean dinner'"
            }
          },
          required: ["query"]
        }
      },
      %{
        name: "search_ingredients",
        description:
          "Search whole-food ingredients (fruit, nuts, cheese, yogurt, vegetables) to use " <>
            "as standalone snack items or light sides. Returns each ingredient's ingredient_id, " <>
            "name, and a list of unit options — each option has a unit_selection value and a " <>
            "human label (e.g. '1 medium', 'gram'). Use an ingredient's ingredient_id plus one " <>
            "of its unit_selection values and a quantity in a submit_plan entry.",
        input_schema: %{
          type: "object",
          properties: %{
            query: %{
              type: "string",
              description:
                "Ingredient name to search for, e.g. 'apple', 'almonds', 'feta cheese', 'greek yogurt'"
            }
          },
          required: ["query"]
        }
      },
      %{
        name: "submit_plan",
        description:
          "Validate and persist the completed 7-day meal plan. " <>
            "Pass all 35 entries at once (5 slots × 7 days). Each entry is EITHER a recipe " <>
            "(set recipe_id and cooking_portions) OR an ingredient (set ingredient_id, quantity, " <>
            "and unit_selection). Returns success with created meal count, or a list of errors " <>
            "to fix before resubmitting.",
        input_schema: %{
          type: "object",
          properties: %{
            entries: %{
              type: "array",
              description: "List of exactly 35 meal entries",
              items: %{
                type: "object",
                properties: %{
                  date: %{type: "string", description: "YYYY-MM-DD"},
                  slot: %{
                    type: "string",
                    description: "One of: #{Enum.join(@slots, ", ")}"
                  },
                  recipe_id: %{type: "integer", description: "For a recipe entry"},
                  cooking_portions: %{type: "integer", description: "Recipe entry: 1–4"},
                  ingredient_id: %{type: "integer", description: "For an ingredient entry"},
                  unit_selection: %{
                    type: "integer",
                    description:
                      "Ingredient entry: a unit_selection value from search_ingredients"
                  },
                  quantity: %{
                    type: "number",
                    description: "Ingredient entry: amount in the chosen unit"
                  }
                },
                required: ["date", "slot"]
              }
            },
            rationale: %{
              type: "string",
              description: "Brief explanation of the plan choices (1–3 sentences)"
            }
          },
          required: ["entries"]
        }
      }
    ]
  end

  # ── tool handlers ─────────────────────────────────────────────────────────────

  defp handle_tool("get_recent_meals", _input, %{user_id: user_id, start_date: start_date} = acc) do
    lookback_start = Date.add(start_date, -@history_days)
    {:ok, start_dt} = NaiveDateTime.new(lookback_start, ~T[00:00:00])
    {:ok, end_dt} = NaiveDateTime.new(start_date, ~T[23:59:59])

    meals = History.list_history_user_meals_for_user(user_id, start_dt, end_dt)

    entries =
      meals
      |> Enum.flat_map(fn meal ->
        date_str = meal.start_dt |> NaiveDateTime.to_date() |> Date.to_string()
        slot = meal.title

        Enum.map(meal.recipe_user_meals, fn rum ->
          %{
            date: date_str,
            slot: slot,
            recipe_title: get_in(rum, [Access.key(:recipe), Access.key(:title)]) || "Unknown"
          }
        end)
      end)

    result =
      if entries == [] do
        %{history: [], message: "No recent meal history found."}
      else
        %{history: entries, count: length(entries)}
      end

    {result, acc}
  end

  defp handle_tool(
         "search_catalog",
         %{"query" => query},
         %{user_id: user_id, offered: offered} = acc
       ) do
    recipes =
      RecipeVectorSearch.search(query, user_id: user_id, limit: 20)
      |> Enum.map(fn r ->
        %{id: r.id, title: r.title, difficulty: r.difficulty || 1, servings: r.servings || 2}
      end)

    acc = %{acc | offered: Enum.reduce(recipes, offered, fn r, s -> MapSet.put(s, r.id) end)}

    result =
      if recipes == [] do
        %{found: false, message: "No recipes found for '#{query}'. Try a different query."}
      else
        %{found: true, count: length(recipes), recipes: recipes}
      end

    {result, acc}
  end

  defp handle_tool(
         "search_ingredients",
         %{"query" => query},
         %{user_id: user_id, offered_ingredients: offered} = acc
       ) do
    ingredients =
      query
      |> Food.IngredientSearch.search([], user_id)
      |> Enum.take(15)
      |> Enum.map(fn i ->
        %{ingredient_id: i.id, name: i.name, units: ingredient_units(i.id)}
      end)

    acc = %{
      acc
      | offered_ingredients:
          Enum.reduce(ingredients, offered, fn i, s -> MapSet.put(s, i.ingredient_id) end)
    }

    result =
      if ingredients == [] do
        %{found: false, message: "No ingredients found for '#{query}'. Try a different query."}
      else
        %{found: true, count: length(ingredients), ingredients: ingredients}
      end

    {result, acc}
  end

  defp handle_tool("submit_plan", %{"entries" => entries} = input, acc) do
    %{
      user_id: user_id,
      start_date: start_date,
      offered: offered,
      offered_ingredients: offered_ing
    } =
      acc

    valid_recipes = Food.list_user_recipes(user_id) |> MapSet.new(& &1.id)
    # Provenance is the real guard for ingredients: every offered id came from a
    # real search result, so the offered set doubles as the valid set.
    valid_ingredients = offered_ing
    end_date = Date.add(start_date, 6)

    errors =
      validate_plan(
        entries,
        offered,
        valid_recipes,
        offered_ing,
        valid_ingredients,
        start_date,
        end_date
      )

    if errors == [] do
      normalized = normalize_entries(entries, start_date)
      rationale = Map.get(input, "rationale", "")

      Logger.info("MealPlanAgent: plan submitted — #{length(normalized)} entries. #{rationale}")

      {%{
         success: true,
         count: length(normalized),
         message: "Plan accepted."
       }, %{acc | submitted: normalized}}
    else
      Logger.warning("MealPlanAgent: submit_plan errors: #{inspect(errors)}")
      {%{success: false, errors: errors}, acc}
    end
  end

  defp handle_tool(name, _input, acc) do
    {%{error: "Unknown tool: #{name}"}, acc}
  end

  # The unit_selection/label options for an ingredient, mirroring the manual meal
  # form's `unit_options/1`: each meaningful portion (positive measurement_unit_id
  # or negative -portion_id) plus grams.
  defp ingredient_units(ingredient_id) do
    portion_units =
      ingredient_id
      |> Food.get_measurement_unit_portions_for_ingredient()
      |> Enum.filter(&IngredientPortion.meaningful_label?(IngredientPortion.display_name(&1)))
      |> Enum.map(fn portion ->
        value = if portion.measurement_unit_id, do: portion.measurement_unit_id, else: -portion.id
        %{unit_selection: value, label: IngredientPortion.display_name(portion) || "portion"}
      end)

    portion_units ++ gram_units()
  end

  defp gram_units do
    Food.get_measurement_unit_by_name("gram")
    |> Enum.map(fn mu -> %{unit_selection: mu.id, label: mu.name} end)
  end

  # ── plan validation ───────────────────────────────────────────────────────────

  @doc """
  Recipe-only validation (kept for the provenance test and backward-compat):
  delegates to the mixed validator with empty ingredient sets.
  """
  def validate_plan(entries, offered, valid_ids, start_date, end_date) do
    validate_plan(
      entries,
      offered,
      valid_ids,
      MapSet.new(),
      MapSet.new(),
      start_date,
      end_date
    )
  end

  @doc false
  def validate_plan(
        entries,
        offered_recipes,
        valid_recipes,
        offered_ingredients,
        valid_ingredients,
        start_date,
        end_date
      ) do
    slot_errors = check_duplicate_slots(entries)

    entry_errors =
      Enum.flat_map(entries, fn entry ->
        validate_entry(
          entry,
          offered_recipes,
          valid_recipes,
          offered_ingredients,
          valid_ingredients,
          start_date,
          end_date
        )
      end)

    slot_errors ++ entry_errors
  end

  defp check_duplicate_slots(entries) do
    entries
    |> Enum.group_by(fn e -> {e["date"], e["slot"]} end)
    |> Enum.filter(fn {_key, group} -> length(group) > 1 end)
    |> Enum.map(fn {{date, slot}, _} -> "Duplicate slot: #{date} #{slot}" end)
  end

  defp validate_entry(
         entry,
         offered_recipes,
         valid_recipes,
         offered_ingredients,
         valid_ingredients,
         start_date,
         end_date
       ) do
    date_slot_errors =
      validate_date(entry, start_date, end_date) ++ validate_slot(entry)

    date_slot_errors ++
      validate_item(entry, offered_recipes, valid_recipes, offered_ingredients, valid_ingredients)
  end

  defp validate_date(entry, start_date, end_date) do
    case Date.from_iso8601(entry["date"] || "") do
      {:ok, date} ->
        if Date.compare(date, start_date) in [:gt, :eq] and
             Date.compare(date, end_date) in [:lt, :eq] do
          []
        else
          ["Date #{entry["date"]} is outside the plan range #{start_date} – #{end_date}"]
        end

      _ ->
        ["Invalid date format '#{entry["date"]}' — use YYYY-MM-DD"]
    end
  end

  defp validate_slot(entry) do
    if entry["slot"] in @slots do
      []
    else
      ["Invalid slot '#{entry["slot"]}' — must be one of: #{Enum.join(@slots, ", ")}"]
    end
  end

  # Exactly one of recipe_id / ingredient_id, then per-kind provenance checks.
  defp validate_item(
         entry,
         offered_recipes,
         valid_recipes,
         offered_ingredients,
         valid_ingredients
       ) do
    recipe_id = entry["recipe_id"]
    ingredient_id = entry["ingredient_id"]

    cond do
      is_integer(recipe_id) and is_integer(ingredient_id) ->
        ["Entry has both recipe_id and ingredient_id — set exactly one: #{inspect(entry)}"]

      is_integer(recipe_id) ->
        validate_recipe_id(recipe_id, offered_recipes, valid_recipes)

      is_integer(ingredient_id) ->
        validate_ingredient_entry(entry, ingredient_id, offered_ingredients, valid_ingredients)

      true ->
        ["Entry needs a recipe_id or ingredient_id: #{inspect(entry)}"]
    end
  end

  defp validate_recipe_id(id, offered, valid) do
    cond do
      # Provenance first: an id the model never received from search_catalog is
      # the dominant failure mode — reject it and steer back to search.
      not MapSet.member?(offered, id) ->
        [
          "recipe_id #{id} was not in your search results — call search_catalog " <>
            "and only use recipe_ids it returns"
        ]

      not MapSet.member?(valid, id) ->
        ["recipe_id #{id} is not in the catalog — use search_catalog to find valid IDs"]

      true ->
        []
    end
  end

  defp validate_ingredient_entry(entry, id, offered, valid) do
    id_errors =
      cond do
        not MapSet.member?(offered, id) ->
          [
            "ingredient_id #{id} was not in your search results — call search_ingredients " <>
              "and only use ingredient_ids it returns"
          ]

        not MapSet.member?(valid, id) ->
          ["ingredient_id #{id} is not a valid ingredient — use search_ingredients"]

        true ->
          []
      end

    quantity_errors =
      case entry["quantity"] do
        q when is_number(q) and q > 0 -> []
        _ -> ["ingredient entry for ingredient_id #{id} needs a positive quantity"]
      end

    id_errors ++ quantity_errors
  end

  # ── entry normalization ───────────────────────────────────────────────────────

  # Turn the model's raw, calendar-dated entries into clean, calendar-independent
  # plan entries: relative `day_index` (1..7), canonical `meal_type`, and either
  # a recipe or an ingredient with its unit resolved to real FKs. The caller
  # decides where these land (calendar or an independent blueprint plan).
  defp normalize_entries(entries, start_date) do
    entries
    |> Enum.filter(fn e ->
      is_binary(e["date"]) and e["slot"] in @slots and
        (is_integer(e["recipe_id"]) or is_integer(e["ingredient_id"]))
    end)
    |> Enum.flat_map(fn e ->
      case normalize_entry(e, start_date) do
        {:ok, entry} -> [entry]
        :error -> []
      end
    end)
  end

  @doc false
  def normalize_entry(entry, start_date) do
    with {:ok, date} <- Date.from_iso8601(entry["date"] || "") do
      base = %{
        day_index: Date.diff(date, start_date) + 1,
        meal_type: Mehungry.History.MealType.from_slot(entry["slot"])
      }

      {:ok, Map.merge(base, item_fields(entry))}
    else
      _ -> :error
    end
  end

  defp item_fields(%{"recipe_id" => recipe_id} = entry) when is_integer(recipe_id) do
    %{
      recipe_id: recipe_id,
      cooking_portions: entry["cooking_portions"] || 2,
      ingredient_id: nil,
      quantity: nil,
      measurement_unit_id: nil,
      ingredient_portion_id: nil
    }
  end

  defp item_fields(%{"ingredient_id" => ingredient_id} = entry) when is_integer(ingredient_id) do
    {mu_id, portion_id} =
      decode_unit(resolve_unit_selection(ingredient_id, entry["unit_selection"]))

    %{
      recipe_id: nil,
      cooking_portions: nil,
      ingredient_id: ingredient_id,
      quantity: (entry["quantity"] || 1) / 1,
      measurement_unit_id: mu_id,
      ingredient_portion_id: portion_id
    }
  end

  # The unit_selection encoding: positive → measurement_unit_id, negative →
  # -ingredient_portion_id (mirrors IngredientUserMeal.apply_unit_selection/1).
  defp decode_unit(sel) when is_integer(sel) and sel >= 0, do: {sel, nil}
  defp decode_unit(sel) when is_integer(sel), do: {nil, -sel}
  defp decode_unit(_), do: {nil, nil}

  # Keep the model's unit_selection only if it's a real unit for this ingredient;
  # otherwise fall back to grams so a bad pick can't create an invalid row.
  defp resolve_unit_selection(ingredient_id, unit_selection) do
    valid =
      ingredient_id
      |> ingredient_units()
      |> MapSet.new(& &1.unit_selection)

    if is_integer(unit_selection) and MapSet.member?(valid, unit_selection) do
      unit_selection
    else
      gram_units() |> List.first() |> then(&(&1 && &1.unit_selection))
    end
  end
end
