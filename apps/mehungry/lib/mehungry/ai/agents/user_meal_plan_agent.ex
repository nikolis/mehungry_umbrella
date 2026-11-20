defmodule Mehungry.AI.Agents.UserMealPlanAgent do
  @moduledoc """
  Meal-plan agent for a person planning **their own** week — the consumer
  calendar, independent blueprint plans, and the mobile "Plan with AI" job.
  (A nutritionist drafting for a client uses `NutritionistMealPlanAgent`.)

  Built on the `AI.Agent` tool-use loop:
    1. Reads the user's recent meal history to avoid repetition
    2. Searches the user's own recipe catalog (per-serving calories included)
    3. Searches whole-food ingredients for the snack slots
    4. Submits the 5-slot × 7-day plan for validation

  What it learns about the person comes from the free-text `preferences` brief
  (the typed prompt, or a blueprint flattened by
  `MealBlueprints.blueprint_preferences/1`). What it is **allowed** to pick is
  enforced deterministically by the shared `MealPlanCore` guards:

    * diet — the blueprint's vegan/vegetarian/pescatarian pattern, else the
      user's profile diet;
    * avoid — the blueprint's `avoid_foods` plus the user's personal avoid list;
    * required hashtags — the blueprint's `required_hashtags` (e.g. `#raw`).

  Returns `{:ok, entries}` — normalized, calendar-independent plan entries (see
  `MealPlanCore.normalize_entries/2`) — or `{:error, reason}`. The agent never
  persists: the caller writes the entries to the calendar
  (`MealPlanGenerator.persist_entries_to_calendar/5`) or to a blueprint plan
  (`MealBlueprints.store_plan_meals/2`).
  """

  alias Mehungry.Accounts
  alias Mehungry.AI.Agent
  alias Mehungry.AI.Agents.MealPlanCore

  @doc """
  Generates a 7-day plan for `user_id` starting at `start_date`.

  - `preferences` — free-text dietary preferences / blueprint brief
  - `start_date`  — `%Date{}` for the first day of the plan
  - `user_id`     — integer
  - `blueprint`   — optional `%Mehungry.MealBlueprints.Blueprint{}` (or nil); its
    targets reach the model through `preferences`, its `avoid_foods` /
    `required_hashtags` / diet pattern drive the guards.
  - `opts`        — `:mode` (`:replace_week` makes `submit_plan` require all three
    main meals on every day, since the plan will replace what is on the week).
  """
  def run(preferences, start_date, user_id, blueprint \\ nil, opts \\ []) do
    guards = guards(user_id, blueprint)

    # `offered`/`offered_ingredients` accumulate every id the search tools handed
    # the model this run; submit_plan rejects any id it never surfaced.
    acc = %{
      user_id: user_id,
      start_date: start_date,
      guards: guards,
      mode: Keyword.get(opts, :mode),
      offered: MapSet.new(),
      offered_ingredients: MapSet.new(),
      submitted: nil
    }

    # One pass, retried once with a firmer instruction if the model answers in
    # prose instead of calling submit_plan (MealPlanCore.run_until_submitted/2).
    result =
      MealPlanCore.run_until_submitted("user_meal_plan", fn extra ->
        Agent.run(
          system_prompt(preferences, start_date, guards),
          initial_message(preferences, start_date) <> extra,
          tool_defs(),
          &handle_tool/3,
          acc,
          telemetry_metadata: %{agent: "user_meal_plan"},
          model: MealPlanCore.model(),
          max_tokens: 4096,
          max_iterations: 14
        )
      end)

    case result do
      {:ok, _text, %{submitted: %{entries: entries}}} -> {:ok, entries}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  The guard set for a user's own plan: their recipes, their blueprint's and
  profile's avoid terms, and the effective diet mode.
  """
  def guards(user_id, blueprint) do
    profile = Accounts.get_user_profile_by_user_id(user_id)

    MealPlanCore.guards(
      catalog: {:user, user_id},
      ingredient_owner_id: user_id,
      avoid_terms: MealPlanCore.avoid_terms(blueprint) ++ MealPlanCore.avoid_terms(profile),
      diet_mode: effective_diet_mode(blueprint, profile),
      required_tags: MealPlanCore.required_recipe_tags(blueprint)
    )
  end

  @doc false
  # The effective diet mode: the blueprint's own pattern if it encodes one, else
  # the user's persisted profile diet. `nil` ⇒ no category diet filter.
  def effective_diet_mode(user_id, blueprint) when is_integer(user_id) do
    effective_diet_mode(blueprint, Accounts.get_user_profile_by_user_id(user_id))
  end

  def effective_diet_mode(blueprint, profile) do
    MealPlanCore.diet_mode_from_blueprint(blueprint) ||
      MealPlanCore.diet_mode_for_diet(profile && profile.diet)
  end

  # ── system prompt ─────────────────────────────────────────────────────────────

  defp system_prompt(preferences, start_date, guards) do
    end_date = Date.add(start_date, 6)
    slots = MealPlanCore.slots()

    """
    You are a personal meal planner creating a 7-day plan.

    Plan period: #{Date.to_string(start_date)} to #{Date.to_string(end_date)} (inclusive).
    Meal slots each day: #{Enum.join(slots, ", ")} (35 total entries).
    User preferences: #{preferences}
    #{MealPlanCore.guard_blocks(guards)}
    WORKFLOW:
    1. Call get_recent_meals to see what the user has eaten lately — avoid heavy repetition
    2. Call search_catalog to find recipes suitable for each main slot:
       - Breakfast: light, quick meals
       - Lunch: moderate meals
       - Dinner: hearty, more complex meals
       You may call search_catalog multiple times with different queries. Each
       result carries per-serving calories — use them to honour any calorie
       target in the preferences
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
    - Slot values must be exactly one of: #{Enum.join(slots, ", ")}
    - submit_plan is the ONLY way to complete the task
    """
  end

  defp initial_message(preferences, start_date) do
    "Create a 7-day, 5-slot-per-day meal plan starting #{Date.to_string(start_date)} " <>
      "with these preferences: #{preferences}"
  end

  # ── tools ─────────────────────────────────────────────────────────────────────

  defp tool_defs do
    [
      %{
        name: "get_recent_meals",
        description:
          "Returns the user's meal history for the past #{MealPlanCore.history_days()} days. " <>
            "Use this first to understand what has been eaten recently and avoid repetition.",
        input_schema: %{type: "object", properties: %{}, required: []}
      },
      MealPlanCore.search_recipes_tool_def("search_catalog"),
      MealPlanCore.search_ingredients_tool_def(),
      MealPlanCore.submit_plan_tool_def("Brief explanation of the plan choices (1–3 sentences)")
    ]
  end

  @doc false
  # Public so handler tests can drive one tool without the Anthropic loop.
  def handle_tool("get_recent_meals", _input, %{user_id: user_id, start_date: start_date} = acc) do
    entries = MealPlanCore.recent_meal_entries(user_id, start_date)

    result =
      if entries == [] do
        %{history: [], message: "No recent meal history found."}
      else
        %{history: entries, count: length(entries)}
      end

    {result, acc}
  end

  def handle_tool("search_catalog", %{"query" => query}, acc),
    do: MealPlanCore.search_recipes_tool(query, acc)

  def handle_tool("search_ingredients", %{"query" => query}, acc),
    do: MealPlanCore.search_ingredients_tool(query, acc)

  def handle_tool("submit_plan", input, acc), do: MealPlanCore.submit_plan_tool(input, acc)

  def handle_tool(name, _input, acc), do: {%{error: "Unknown tool: #{name}"}, acc}
end
