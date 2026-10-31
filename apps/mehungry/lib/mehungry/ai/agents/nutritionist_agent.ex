defmodule Mehungry.AI.Agents.NutritionistAgent do
  @moduledoc """
  AI agent for nutritionist professionals.

  Given a client, the agent:
    1. Reads the client's recent meal history and ratings
    2. Searches the professional's recipe catalog for suitable meals
    3. Submits a validated 7-day plan that gets persisted to the client's account

  Progress is reported via an `on_event` callback injected by the caller
  (typically the Oban worker), which broadcasts to PubSub so the LiveView
  can show streaming status without polling.
  """

  require Logger
  alias Mehungry.{Accounts, Food, Health, History, Professionals, AI.Agent, Search.RecipeVectorSearch}
  alias Mehungry.History.MealType
  alias Mehungry.AI.Agents.MealPlanAgent
  alias Mehungry.AI.MealPlanGenerator

  @model "claude-haiku-4-5-20251001"
  @history_days 21

  # The 5 calendar slots, in the label form the model emits and
  # MealType.from_slot/1 maps back to canonical values. Snacks (Morning/Afternoon)
  # are typically a single whole-food ingredient rather than a recipe.
  @slots ["Breakfast", "Morning Snack", "Lunch", "Afternoon Snack", "Dinner"]

  @doc """
  Drafts and persists a 7-day meal plan for `client_id` on behalf of `professional_id`.

  Options:
    - `:on_event` — `fn(event) -> :ok` called before and after each tool call.
      Events: `{:tool_call, name}` and `{:tool_result, name, result}`.
      Defaults to a no-op.

  Returns `{:ok, summary_text}` or `{:error, reason}`.
  """
  def run(professional_id, client_id, preferences, opts \\ []) do
    on_event = Keyword.get(opts, :on_event, fn _ -> :ok end)

    acc = new_acc(professional_id, client_id)

    handler = fn name, input, acc ->
      on_event.({:tool_call, name})
      {result, acc} = handle_tool(name, input, acc)
      on_event.({:tool_result, name, result})
      {result, acc}
    end

    result =
      Agent.run(
        system_prompt(preferences, acc.start_date),
        "Draft a 7-day meal plan for this client. Preferences: #{preferences}",
        tool_defs(),
        handler,
        acc,
        telemetry_metadata: %{agent: "nutritionist"},
        model: @model,
        max_tokens: 4096,
        max_iterations: 16
      )

    case result do
      {:ok, summary, %{submitted: nil}} ->
        {:ok, summary}

      {:ok, summary, %{submitted: {:plan_created, count}}} ->
        {:ok, "#{summary}\n\n✓ #{count} meal entries created."}

      error ->
        error
    end
  end

  # ── system prompt ─────────────────────────────────────────────────────────────

  defp system_prompt(preferences, start_date) do
    end_date = Date.add(start_date, 6)

    """
    You are an AI assistant for a professional nutritionist.
    Your task is to draft a personalised 7-day meal plan for a client.

    Plan period: #{Date.to_string(start_date)} to #{Date.to_string(end_date)}.
    Meal slots each day: Breakfast, Morning Snack, Lunch, Afternoon Snack, Dinner
    (up to 35 entries over 7 days — fewer if the nutritionist has already assigned some cells).
    Client preferences / notes: #{preferences}

    WORKFLOW:
    1. Call get_client_record FIRST — the nutritionist's file for this client:
       diet, foods to avoid (allergies/intolerances + condition-implicated foods),
       health conditions, goal, anthropometrics, daily calorie target, and the
       latest consultation note. This is the most important input — honour it.
    2. Call get_assigned_plan to see which (date, slot) cells the nutritionist has
       ALREADY assigned for this week. Leave those in place — only fill empty cells.
    3. Call get_client_summary to understand the client's recent activity
    4. Call get_recent_meals to see what the client has eaten lately (avoid repetition)
    5. Call get_ratings to understand which types of meals the client rated well or poorly
    6. Call search_recipes one or more times to find suitable recipes for the three
       main slots. Each result carries difficulty (1 = quick/light, 3 = demanding)
       and per-serving calories — use them to place recipes and to keep each day
       near the client's calorie target
    7. Call search_ingredients to find whole-food snack items for the two snack slots —
       snacks should be a single whole food (e.g. a banana, 20 g of almonds, Greek
       yogurt), NOT a recipe
    8. Draft the plan — 5 slots × 7 days, MINUS any cells already filled in
       get_assigned_plan (do not include those)
    9. Call submit_plan with the entries and a 2–3 sentence professional rationale
    10. If submit_plan returns errors, fix them and resubmit

    RULES:
    - Each entry is EITHER a recipe (recipe_id + cooking_portions) OR an ingredient
      (ingredient_id + quantity, optional unit_selection) — never both
    - Only use recipe_ids returned by search_recipes and ingredient_ids returned by
      search_ingredients — never invent IDs
    - DIET: respect the client's diet from get_client_record. If it is vegetarian or
      vegan, never select meat, poultry, or fish (nor a recipe containing them) —
      search with diet-appropriate queries.
    - AVOID LIST: never select any recipe or ingredient whose name (or obvious
      contents) matches a food on the client's `avoid` list from get_client_record
      (allergies, intolerances, personal avoid, condition-implicated foods). If in
      doubt, choose something else.
    - CALORIE TARGET: when get_client_record returns a calorie_target, aim each day's
      total calories within about ±10% of it using the per-serving calories from
      search_recipes; do not materially exceed it.
    - ASSIGNED PLAN: never fill a (date, slot) that get_assigned_plan listed as
      already assigned — leave the nutritionist's meals untouched and fill only the
      remaining empty cells.
    - SNACKS: the two snack slots (Morning Snack, Afternoon Snack) must favour a
      single whole-food ingredient (fruit, nuts, yogurt, cheese) over a recipe —
      e.g. 1 banana, 20 g of almonds, a cup of Greek yogurt. A person should be able
      to grab them with no cooking. Use search_ingredients, not a recipe, for these.
    - For ingredients, pick a unit_selection from the options search_ingredients
      returned and a sensible quantity (e.g. 1 banana, 20 g of almonds)
    - BREAKFAST: always quick and simple to prepare — a low-difficulty recipe or a
      simple whole-food plate. Never a demanding dish in the morning.
    - LUNCH IS THE MAIN MEAL: lunch should be the most intense/substantial meal of
      the day. The day's single demanding/heavy recipe (difficulty 3, e.g. ribs,
      fasolada, a slow-cooked stew) belongs at Lunch — at most one such dish per day.
      Be pragmatic about what a client can realistically cook.
    - DINNER IS LIGHTER: dinner must be lighter than lunch — a salad, soup, or
      simple plate. Never make dinner heavier than lunch, and never put two heavy
      main meals on the same day. If lunch is a light legume/vegetable dish (e.g.
      beans), dinner may be similar.
    - Vary recipes to minimise repetition, especially for recipes seen in recent history
    - Slot values must be exactly one of: #{Enum.join(@slots, ", ")}
    - Write the rationale as a professional note the nutritionist can show the client
    - submit_plan is the ONLY way to finish — always call it
    """
  end

  # ── tool definitions ──────────────────────────────────────────────────────────

  defp tool_defs do
    [
      %{
        name: "get_client_summary",
        description:
          "Returns basic info about the client: name, email, number of recent meals, " <>
            "and average rating score. Call this first.",
        input_schema: %{type: "object", properties: %{}, required: []}
      },
      %{
        name: "get_recent_meals",
        description:
          "Returns the client's meal history for the past #{@history_days} days. " <>
            "Each entry has date, slot (Breakfast/Lunch/Dinner), and recipe title. " <>
            "Use this to avoid repeating meals the client just had.",
        input_schema: %{type: "object", properties: %{}, required: []}
      },
      %{
        name: "get_ratings",
        description:
          "Returns the client's meal plan ratings with scores (1–5) and optional comments. " <>
            "Use this to understand which types of food the client enjoys.",
        input_schema: %{type: "object", properties: %{}, required: []}
      },
      %{
        name: "get_client_record",
        description:
          "Returns the nutritionist's structured file for this client plus the client's " <>
            "own profile: diet, lactose intolerance, a calorie_target, linked health " <>
            "conditions, the goal, anthropometrics (weight/BMI/TDEE/etc.), the latest " <>
            "consultation note, and an `avoid` list of foods to never use (allergies, " <>
            "intolerances, the client's personal avoid list, and foods implicated by " <>
            "the client's conditions). Call this FIRST and honour it throughout the plan.",
        input_schema: %{type: "object", properties: %{}, required: []}
      },
      %{
        name: "get_assigned_plan",
        description:
          "Returns the meals the nutritionist has ALREADY assigned to this client's " <>
            "calendar for the plan week. Each entry has date, slot, and the assigned " <>
            "items. Do NOT fill those (date, slot) cells — leave them in place and only " <>
            "fill the remaining empty cells. Also use the assigned items to avoid repetition.",
        input_schema: %{type: "object", properties: %{}, required: []}
      },
      %{
        name: "search_recipes",
        description:
          "Semantically search the professional's recipe catalog. " <>
            "Returns recipe_id, title, difficulty (1–3), servings, and per-serving " <>
            "calories (use these to keep each day near the client's calorie target). " <>
            "Use natural language queries like 'light chicken breakfast', " <>
            "'high protein vegetarian dinner', or 'quick pasta lunch'. " <>
            "Call multiple times with different queries to build a slot-appropriate selection.",
        input_schema: %{
          type: "object",
          properties: %{
            query: %{
              type: "string",
              description:
                "Natural language query, e.g. 'light high-protein breakfast', 'Mediterranean fish dinner', 'quick vegetarian lunch'"
            }
          },
          required: ["query"]
        }
      },
      %{
        name: "search_ingredients",
        description:
          "Search whole-food ingredients (fruit, nuts, cheese, yogurt, vegetables) to use " <>
            "as standalone snack items for the two snack slots. Returns each ingredient's " <>
            "ingredient_id, name, and a list of unit options — each option has a unit_selection " <>
            "value and a human label (e.g. '1 medium', 'gram'). Use an ingredient's ingredient_id " <>
            "plus one of its unit_selection values and a quantity in a submit_plan entry.",
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
          "Validate and persist the 7-day meal plan for the client. " <>
            "Pass all 35 entries at once (5 slots × 7 days). Each entry is EITHER a recipe " <>
            "(set recipe_id and cooking_portions) OR an ingredient (set ingredient_id, quantity, " <>
            "and unit_selection). Returns success with a count of created entries, or errors to fix.",
        input_schema: %{
          type: "object",
          properties: %{
            entries: %{
              type: "array",
              description: "35 meal entries covering 7 days × 5 slots",
              items: %{
                type: "object",
                properties: %{
                  date: %{type: "string", description: "YYYY-MM-DD"},
                  slot: %{type: "string", description: "One of: #{Enum.join(@slots, ", ")}"},
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
              description:
                "2–3 sentence professional note explaining the plan choices for this client"
            }
          },
          required: ["entries", "rationale"]
        }
      }
    ]
  end

  # ── tool handlers ─────────────────────────────────────────────────────────────

  @doc false
  # The run accumulator. `offered`/`offered_ingredients` collect every id the search
  # tools handed the model (provenance gate in submit_plan); `occupied` collects the
  # (date, slot) cells the nutritionist already assigned (so submit_plan leaves them
  # in place); `submitted` carries the outcome back to the caller. No process-global
  # state. Public so handler tests can build a run context.
  def new_acc(professional_id, client_id) do
    %{
      professional_id: professional_id,
      client_id: client_id,
      start_date: Date.utc_today(),
      offered: MapSet.new(),
      offered_ingredients: MapSet.new(),
      occupied: MapSet.new(),
      submitted: nil
    }
  end

  @doc false
  # Test seam: exercise one tool handler with a given accumulator, bypassing the
  # Anthropic loop. Returns `{result, new_acc}`.
  def handle_tool(name, input, acc), do: do_handle_tool(name, input, acc)

  defp do_handle_tool(
         "get_client_summary",
         _input,
         %{client_id: client_id, start_date: start_date} = acc
       ) do
    client = Mehungry.Accounts.get_user!(client_id)

    lookback = Date.add(start_date, -@history_days)
    {:ok, lbdt} = NaiveDateTime.new(lookback, ~T[00:00:00])
    {:ok, end_dt} = NaiveDateTime.new(start_date, ~T[23:59:59])

    recent_meals = History.list_history_user_meals_for_user(client_id, lbdt, end_dt)
    ratings = Professionals.list_ratings_for_client(client_id)

    avg_rating =
      if ratings == [] do
        nil
      else
        scores = Enum.map(ratings, & &1.score)
        Float.round(Enum.sum(scores) / length(scores), 1)
      end

    {%{
       name: client.name || client.email,
       email: client.email,
       recent_meal_count: length(recent_meals),
       rating_count: length(ratings),
       avg_rating: avg_rating
     }, acc}
  end

  defp do_handle_tool(
         "get_recent_meals",
         _input,
         %{client_id: client_id, start_date: start_date} = acc
       ) do
    lookback = Date.add(start_date, -@history_days)
    {:ok, lbdt} = NaiveDateTime.new(lookback, ~T[00:00:00])
    {:ok, end_dt} = NaiveDateTime.new(start_date, ~T[23:59:59])

    meals = History.list_history_user_meals_for_user(client_id, lbdt, end_dt)

    entries =
      Enum.flat_map(meals, fn meal ->
        date_str = meal.start_dt |> NaiveDateTime.to_date() |> Date.to_string()

        Enum.map(meal.recipe_user_meals, fn rum ->
          title = get_in(rum, [Access.key(:recipe), Access.key(:title)]) || "Unknown"
          %{date: date_str, slot: meal.title, recipe: title}
        end)
      end)

    {%{recent_meals: entries, count: length(entries)}, acc}
  end

  defp do_handle_tool("get_ratings", _input, %{client_id: client_id} = acc) do
    ratings = Professionals.list_ratings_for_client(client_id)

    entries =
      Enum.map(ratings, fn r ->
        %{
          score: r.score,
          type: r.rating_type,
          comment: r.comment,
          date: r.inserted_at |> NaiveDateTime.to_date() |> Date.to_string()
        }
      end)

    {%{ratings: entries, count: length(entries)}, acc}
  end

  defp do_handle_tool(
         "get_client_record",
         _input,
         %{professional_id: professional_id, client_id: client_id} = acc
       ) do
    record = Professionals.get_client_record_by_user(professional_id, client_id)
    profile = Accounts.get_user_profile_by_user_id(client_id)
    intake = record && Professionals.get_latest_intake(record.id)
    conditions = if record, do: Professionals.list_client_conditions(record.id), else: []
    latest_note = record && (record.id |> Professionals.list_consultation_notes() |> List.last())

    result = %{
      has_record: not is_nil(record),
      diet: (profile && profile.diet) || "omnivore",
      lactose_intolerant: (profile && profile.lactose_intolerant) || false,
      calorie_target: calorie_target(intake, profile),
      goal: intake && intake.goal,
      conditions: Enum.map(conditions, & &1.name),
      avoid: avoid_list(profile, intake, conditions),
      anthropometrics: anthropometrics_summary(intake),
      latest_note: latest_note && %{body: latest_note.body, todo: latest_note.todo}
    }

    {result, acc}
  end

  defp do_handle_tool(
         "get_assigned_plan",
         _input,
         %{client_id: client_id, start_date: start_date, occupied: occupied} = acc
       ) do
    meals = assigned_meals(client_id, start_date)
    entries = Enum.map(meals, &assigned_entry/1) |> Enum.sort_by(&{&1.date, &1.slot})

    new_occupied =
      Enum.reduce(entries, occupied, fn e, set -> MapSet.put(set, {e.date, e.slot}) end)

    result = %{
      assigned_count: length(entries),
      assigned_entries: entries,
      message: assigned_plan_message(entries)
    }

    {result, %{acc | occupied: new_occupied}}
  end

  defp do_handle_tool(
         "search_recipes",
         %{"query" => query},
         %{professional_id: professional_id, offered: offered} = acc
       ) do
    recipes =
      RecipeVectorSearch.search(query, user_id: professional_id, limit: 20)
      |> Enum.map(fn r ->
        %{
          recipe_id: r.id,
          title: r.title,
          difficulty: r.difficulty || 1,
          servings: r.servings || 2,
          calories: per_serving_calories(r)
        }
      end)

    acc = %{
      acc
      | offered: Enum.reduce(recipes, offered, fn r, s -> MapSet.put(s, r.recipe_id) end)
    }

    result =
      if recipes == [] do
        %{found: false, message: "No recipes found for '#{query}'. Try a different query."}
      else
        %{found: true, count: length(recipes), recipes: recipes}
      end

    {result, acc}
  end

  defp do_handle_tool(
         "search_ingredients",
         %{"query" => query},
         %{professional_id: professional_id, offered_ingredients: offered} = acc
       ) do
    ingredients =
      query
      |> Food.IngredientSearch.search([], professional_id)
      |> Enum.take(15)
      |> Enum.map(fn i ->
        %{ingredient_id: i.id, name: i.name, units: MealPlanAgent.ingredient_units(i.id)}
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

  defp do_handle_tool("submit_plan", %{"entries" => entries} = input, acc) do
    %{
      client_id: client_id,
      start_date: start_date,
      professional_id: professional_id,
      offered: offered,
      offered_ingredients: offered_ingredients,
      occupied: occupied
    } = acc

    rationale = Map.get(input, "rationale", "")

    valid_recipes = Food.list_user_recipes(professional_id) |> MapSet.new(& &1.id)
    # Provenance is the guard for ingredients: every offered id came from a real
    # search result, so the offered set doubles as the valid set.
    valid_ingredients = offered_ingredients
    end_date = Date.add(start_date, 6)

    errors =
      MealPlanAgent.validate_plan(
        entries,
        offered,
        valid_recipes,
        offered_ingredients,
        valid_ingredients,
        start_date,
        end_date
      )

    if errors == [] do
      persist_validated_plan(entries, occupied, client_id, start_date, rationale, acc)
    else
      {%{success: false, errors: errors}, acc}
    end
  end

  defp do_handle_tool(name, _input, acc) do
    {%{error: "Unknown tool: #{name}"}, acc}
  end

  # Persist a validated plan, but never overwrite a cell the nutritionist already
  # assigned — drop any entry whose (date, slot) is in the occupied set captured by
  # get_assigned_plan, and report how many cells were left in place.
  defp persist_validated_plan(entries, occupied, client_id, start_date, rationale, acc) do
    {to_create, protected} =
      Enum.split_with(entries, fn e ->
        not MapSet.member?(occupied, {e["date"], e["slot"]})
      end)

    {created, skipped} = persist_entries(to_create, client_id, start_date)

    Logger.info(
      "NutritionistAgent: plan created — #{length(created)} meals for client #{client_id} " <>
        "(#{length(protected)} assigned cells left in place). #{rationale}"
    )

    {%{
       success: true,
       created: length(created),
       skipped: skipped,
       left_assigned: length(protected),
       rationale: rationale,
       message: "Plan created successfully."
     }, %{acc | submitted: {:plan_created, length(created)}}}
  end

  # ── tool helpers ──────────────────────────────────────────────────────────────

  # Daily calorie target: the intake's TDEE wins (clinician-assessed), else the
  # client's own profile target, else nil.
  defp calorie_target(intake, profile) do
    cond do
      intake && intake.tdee_kcal -> intake.tdee_kcal
      profile && profile.daily_calorie_target -> profile.daily_calorie_target
      true -> nil
    end
  end

  # Unified list of foods to never use: the client's personal avoid list + intake
  # allergy/intolerance terms + condition-implicated foods resolved through the same
  # curated Health engine the /foods filter uses (condition → "avoid" compound
  # recommendations → species → ingredients). Deduped + capped.
  defp avoid_list(profile, intake, conditions) do
    condition_avoid =
      conditions
      |> Enum.flat_map(fn c -> Health.ingredients_for_condition(c.id, "avoid") end)
      |> Enum.map(& &1.ingredient.name)

    [(profile && profile.avoid_foods) || [], intake_avoid_terms(intake), condition_avoid]
    |> List.flatten()
    |> Enum.map(&String.trim(to_string(&1)))
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.take(40)
  end

  defp anthropometrics_summary(nil), do: nil

  defp anthropometrics_summary(intake) do
    %{
      weight_kg: intake.weight_kg,
      bmi: intake.bmi,
      sex: intake.sex,
      age: intake.age,
      activity_level: intake.activity_level,
      tdee_kcal: intake.tdee_kcal,
      bmr_kcal: intake.bmr_kcal
    }
  end

  # Avoid terms from a client intake's free-form `details` JSONB (allergies,
  # intolerances, aversions). Each value may be a list or a comma/newline-separated
  # string; both are flattened into discrete terms.
  defp intake_avoid_terms(%{details: details}) when is_map(details) do
    ~w(allergies food_intolerances food_aversions)
    |> Enum.flat_map(fn key -> details |> Map.get(key) |> split_terms() end)
  end

  defp intake_avoid_terms(_), do: []

  defp split_terms(value) when is_list(value), do: Enum.map(value, &to_string/1)
  defp split_terms(value) when is_binary(value), do: String.split(value, ~r/[,;\n]/, trim: true)
  defp split_terms(_), do: []

  # The client's calendar meals for the plan week that land in one of the 5 slots.
  defp assigned_meals(client_id, start_date) do
    client_id
    |> History.list_calendar_user_meals(start_date, Date.add(start_date, 6))
    |> Enum.filter(&(MealType.label(&1.meal_type) in @slots))
  end

  defp assigned_entry(meal) do
    %{
      date: meal.start_dt |> NaiveDateTime.to_date() |> Date.to_string(),
      slot: MealType.label(meal.meal_type),
      items: assigned_items(meal)
    }
  end

  defp assigned_plan_message([]),
    do: "No meals are assigned for this week — fill all 35 slots."

  defp assigned_plan_message(_entries),
    do: "These (date, slot) cells are already assigned — do NOT fill them; fill only the empty cells."

  # Display names of the recipes/ingredients assigned to a calendar meal.
  defp assigned_items(meal) do
    recipe_titles =
      Enum.map(meal.recipe_user_meals || [], fn rum ->
        get_in(rum, [Access.key(:recipe), Access.key(:title)]) || "Unknown"
      end)

    ingredient_names =
      Enum.map(meal.ingredient_user_meals || [], fn ium ->
        get_in(ium, [Access.key(:ingredient), Access.key(:name)]) || "Unknown"
      end)

    recipe_titles ++ ingredient_names
  end

  # Per-serving kcal from a recipe's stored aggregate `nutrients` tree, reusing the
  # same `NutrientUtils.macro_summary/1` the calendar + SEO JSON-LD use. nil when
  # there's no usable energy value.
  defp per_serving_calories(%{nutrients: nutrients} = recipe)
       when is_map(nutrients) and map_size(nutrients) > 0 do
    case Mehungry.NutrientUtils.macro_summary(nutrients).energy_kcal do
      kcal when is_number(kcal) and kcal > 0 ->
        servings = if is_integer(recipe.servings) and recipe.servings > 0, do: recipe.servings, else: 1
        round(kcal / servings)

      _ ->
        nil
    end
  end

  defp per_serving_calories(_), do: nil

  # ── plan validation ───────────────────────────────────────────────────────────

  @doc """
  Recipe-only validation seam kept for the provenance test and backward-compat;
  delegates to `MealPlanAgent.validate_plan/5` (shared recipe + ingredient
  validator, 5-slot vocabulary).
  """
  def validate_entries(entries, offered, valid_ids, start_date, end_date) do
    MealPlanAgent.validate_plan(entries, offered, valid_ids, start_date, end_date)
  end

  # ── record creation ───────────────────────────────────────────────────────────

  # Normalize the model's raw entries to calendar-independent form (resolving
  # ingredient unit FKs) then reuse the shared calendar persister, which writes
  # `meal_type` (so meals land in the right slot, not "Unsorted") and supports both
  # recipe and ingredient entries.
  defp persist_entries(entries, client_id, start_date) do
    normalized =
      entries
      |> Enum.filter(fn e ->
        is_binary(e["date"]) and e["slot"] in @slots and
          (is_integer(e["recipe_id"]) or is_integer(e["ingredient_id"]))
      end)
      |> Enum.flat_map(fn e ->
        case MealPlanAgent.normalize_entry(e, start_date) do
          {:ok, entry} -> [entry]
          :error -> []
        end
      end)

    {:ok, created, skipped} =
      MealPlanGenerator.persist_entries_to_calendar(normalized, client_id, start_date)

    {created, skipped}
  end
end
