defmodule Mehungry.AI.Agents.NutritionistMealPlanAgent do
  @moduledoc """
  Meal-plan agent for a **nutritionist drafting a client's week** — the only
  meal-plan agent surfaced on the nutritionist side (client file "AI Assist" and
  the client calendar). A person planning their own week uses
  `UserMealPlanAgent`.

  The two agents share every guarantee through `MealPlanCore` (guarded search,
  provenance, validation, normalization). This one differs only in **how it
  learns about the person**: instead of a free-text brief it reads the client
  through tools —

    * `get_client_record` — the nutritionist's file merged with the client's
      profile (`Professionals.resolve_client_meal_context/2`): diet, avoid list,
      conditions, goal, anthropometrics, calorie target, latest note;
    * `get_assigned_plan` — the cells already on the client's calendar that week;
    * `get_client_summary`, `get_recent_meals`, `get_ratings`.

  The same resolved client context also builds the deterministic guards: the
  client's diet, every avoid term, and the exact condition-implicated ingredient
  ids are filtered out of the search results, so the model is never offered a
  food the client must avoid.

  Recipes come from the nutritionist's own catalog, or the public catalog when
  they have authored none (`MealPlanCore.catalog_for_professional/1`).

  Like `UserMealPlanAgent`, this agent only **generates**. It returns
  `{:ok, %{entries, rationale, summary}}`; the caller
  (`NutritionistAgentWorker`) writes the entries to the client's calendar in the
  chosen mode (`MealPlanGenerator.persist_entries_to_calendar/5`).

  Progress is reported via an `on_event` callback so the worker can broadcast
  live steps over PubSub.
  """

  alias Mehungry.{History, Professionals}
  alias Mehungry.AI.Agent
  alias Mehungry.AI.Agents.MealPlanCore
  alias Mehungry.History.MealType

  @doc """
  Drafts a 7-day plan for `client_id` on behalf of `professional_id`.

  Options:
    - `:start_date` — first day of the plan (default: Monday of the current week)
    - `:mode` — `:fill_gaps` (default; the model is told which cells are taken and
      to leave them) or `:replace_week` (the week is rebuilt, all 35 slots)
    - `:on_event` — `fn(event) -> :ok`, called with `{:tool_call, name}` and
      `{:tool_result, name, result}`

  Returns `{:ok, %{entries: [...], rationale: text, summary: text}}` or
  `{:error, reason}`.
  """
  def run(professional_id, client_id, preferences, opts \\ []) do
    on_event = Keyword.get(opts, :on_event, fn _ -> :ok end)
    acc = new_acc(professional_id, client_id, opts)

    handler = fn name, input, acc ->
      on_event.({:tool_call, name})
      {result, acc} = handle_tool(name, input, acc)
      on_event.({:tool_result, name, result})
      {result, acc}
    end

    # One pass, retried once with a firmer instruction if the model answers in
    # prose instead of calling submit_plan (MealPlanCore.run_until_submitted/2).
    result =
      MealPlanCore.run_until_submitted("nutritionist_meal_plan", fn extra ->
        Agent.run(
          system_prompt(preferences, acc),
          "Draft a 7-day meal plan for this client. Preferences: #{preferences}" <> extra,
          tool_defs(),
          handler,
          acc,
          telemetry_metadata: %{agent: "nutritionist_meal_plan"},
          model: MealPlanCore.model(),
          max_tokens: 4096,
          max_iterations: 16
        )
      end)

    case result do
      {:ok, summary, %{submitted: %{entries: entries, rationale: rationale}, guards: guards}} ->
        {:ok,
         %{
           entries: entries,
           rationale: rationale,
           summary: summary,
           avoided: MealPlanCore.enforced_avoid_terms(guards)
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  The avoid terms a draft for this client enforces — shown to the nutritionist
  with the result (or the failure), so a filtered-down catalog is never a mystery.
  """
  def enforced_avoid_terms(professional_id, client_id) do
    professional_id
    |> new_acc(client_id)
    |> Map.fetch!(:guards)
    |> MealPlanCore.enforced_avoid_terms()
  end

  @doc "Monday of the current week — the default plan anchor."
  def default_start_date, do: Date.beginning_of_week(Date.utc_today())

  # ── system prompt ─────────────────────────────────────────────────────────────

  defp system_prompt(preferences, %{start_date: start_date, guards: guards, mode: mode} = acc) do
    end_date = Date.add(start_date, 6)
    first_day = acc.first_day
    max_entries = 5 * (Date.diff(end_date, first_day) + 1)
    slots = MealPlanCore.slots()

    """
    You are an AI assistant for a professional nutritionist.
    Your task is to draft a personalised 7-day meal plan for a client.

    Plan period: #{Date.to_string(first_day)} to #{Date.to_string(end_date)} (inclusive —
    never plan a date before #{Date.to_string(first_day)}).
    Meal slots each day: #{Enum.join(slots, ", ")}
    (up to #{max_entries} entries).
    Client preferences / notes: #{preferences}
    #{MealPlanCore.guard_blocks(guards)}
    WORKFLOW:
    1. Call get_client_record FIRST — the nutritionist's file for this client:
       diet, foods to avoid (allergies/intolerances + condition-implicated foods),
       health conditions, goal, anthropometrics, daily calorie target, and the
       latest consultation note. This is the most important input — honour it.
    2. Call get_assigned_plan to see what is already on the client's calendar this
       week. #{assigned_instruction(mode)}
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
    8. Draft the plan
    9. Call submit_plan with the entries and a 2–3 sentence professional rationale
    10. If submit_plan returns errors, fix them and resubmit

    RULES:
    - Each entry is EITHER a recipe (recipe_id + cooking_portions) OR an ingredient
      (ingredient_id + quantity, optional unit_selection) — never both
    - Only use recipe_ids returned by search_recipes and ingredient_ids returned by
      search_ingredients — never invent IDs
    - DIET: respect the client's diet from get_client_record. The search tools
      already return only diet-compatible results — build the plan from those.
    - AVOID LIST: never select any recipe or ingredient whose name (or obvious
      contents) matches a food on the client's `avoid` list from get_client_record
      (allergies, intolerances, personal avoid, condition-implicated foods). If in
      doubt, choose something else.
    - CALORIE TARGET: when get_client_record returns a calorie_target, aim each day's
      total calories within about ±10% of it using the per-serving calories from
      search_recipes; do not materially exceed it.
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
    - Slot values must be exactly one of: #{Enum.join(slots, ", ")}
    - Write the rationale as a professional note the nutritionist can show the client
    - submit_plan is the ONLY way to finish — always call it
    """
  end

  defp assigned_instruction(:replace_week),
    do:
      "The nutritionist chose to REPLACE the week: those meals will be removed, so " <>
        "plan every slot in the period (use the existing items only to avoid repeating them)."

  defp assigned_instruction(_fill_gaps),
    do:
      "The nutritionist chose to FILL GAPS: leave every listed (date, slot) cell " <>
        "untouched and plan only the empty cells."

  # ── tool definitions ──────────────────────────────────────────────────────────

  defp tool_defs do
    [
      %{
        name: "get_client_summary",
        description:
          "Returns basic info about the client: first name, number of recent meals, " <>
            "and average rating score.",
        input_schema: %{type: "object", properties: %{}, required: []}
      },
      %{
        name: "get_recent_meals",
        description:
          "Returns the client's meal history for the past #{MealPlanCore.history_days()} days. " <>
            "Each entry has date, slot, and recipe title. " <>
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
          "Returns the meals already on this client's calendar for the plan week. Each " <>
            "entry has date, slot, and the assigned items. The result's message says " <>
            "whether to leave those cells in place or plan the whole week.",
        input_schema: %{type: "object", properties: %{}, required: []}
      },
      MealPlanCore.search_recipes_tool_def("search_recipes"),
      MealPlanCore.search_ingredients_tool_def(),
      MealPlanCore.submit_plan_tool_def(
        "2–3 sentence professional note explaining the plan choices for this client",
        true
      )
    ]
  end

  # ── run accumulator ───────────────────────────────────────────────────────────

  @doc false
  # The run accumulator. The client context is resolved **once** here: it is what
  # `get_client_record` returns and what the guards are built from, so the model's
  # brief and the deterministic filters can never disagree. Public so handler
  # tests can build a run context.
  def new_acc(professional_id, client_id, opts \\ []) do
    context = Professionals.resolve_client_meal_context(professional_id, client_id)
    start_date = Keyword.get(opts, :start_date) || default_start_date()

    %{
      professional_id: professional_id,
      client_id: client_id,
      start_date: start_date,
      # A client's past days hold what they actually ate; a draft never plans them.
      first_day: first_day(start_date),
      mode: Keyword.get(opts, :mode) || :fill_gaps,
      context: context,
      guards: guards(professional_id, context),
      offered: MapSet.new(),
      offered_ingredients: MapSet.new(),
      submitted: nil
    }
  end

  @doc """
  The first day a draft for the week starting `start_date` may plan: today when
  the week has already begun, else the week start.
  """
  def first_day(%Date{} = start_date, today \\ Date.utc_today()) do
    if Date.compare(today, start_date) == :gt, do: today, else: start_date
  end

  defp guards(professional_id, context) do
    MealPlanCore.guards(
      catalog: MealPlanCore.catalog_for_professional(professional_id),
      ingredient_owner_id: professional_id,
      # Curated terms (avoid chips, condition foods) match as substrings; the
      # intake's free text is cleaned and matched at word starts only.
      avoid_terms: context.avoid -- context.avoid_free_text,
      avoid_word_terms: context.avoid_free_text,
      avoid_ingredient_ids: context.avoid_ingredient_ids,
      diet_mode: MealPlanCore.diet_mode_for_diet(context.diet)
    )
  end

  # ── tool handlers ─────────────────────────────────────────────────────────────

  @doc false
  # Test seam: exercise one tool handler with a given accumulator, bypassing the
  # Anthropic loop. Returns `{result, new_acc}`.
  def handle_tool(
        "get_client_summary",
        _input,
        %{client_id: client_id, start_date: start_date} = acc
      ) do
    client = Mehungry.Accounts.get_user!(client_id)
    recent = MealPlanCore.recent_meal_entries(client_id, start_date)
    ratings = Professionals.list_ratings_for_client(client_id)

    avg_rating =
      if ratings == [] do
        nil
      else
        scores = Enum.map(ratings, & &1.score)
        Float.round(Enum.sum(scores) / length(scores), 1)
      end

    # Data minimisation: the model plans meals, it has no use for contact details.
    {%{
       name: first_name(client.name),
       recent_meal_count: length(recent),
       rating_count: length(ratings),
       avg_rating: avg_rating
     }, acc}
  end

  def handle_tool("get_recent_meals", _input, %{client_id: client_id, start_date: start} = acc) do
    entries = MealPlanCore.recent_meal_entries(client_id, start)
    {%{recent_meals: entries, count: length(entries)}, acc}
  end

  def handle_tool("get_ratings", _input, %{client_id: client_id} = acc) do
    entries =
      client_id
      |> Professionals.list_ratings_for_client()
      |> Enum.map(fn r ->
        %{
          score: r.score,
          type: r.rating_type,
          comment: r.comment,
          date: r.inserted_at |> NaiveDateTime.to_date() |> Date.to_string()
        }
      end)

    {%{ratings: entries, count: length(entries)}, acc}
  end

  def handle_tool("get_client_record", _input, %{context: context} = acc) do
    # The ingredient ids and the free-text split are for the guards, not the model.
    {Map.drop(context, [:avoid_ingredient_ids, :avoid_free_text]), acc}
  end

  def handle_tool(
        "get_assigned_plan",
        _input,
        %{client_id: client_id, start_date: start_date, first_day: first_day, mode: mode} = acc
      ) do
    entries =
      client_id
      |> assigned_meals(first_day, Date.add(start_date, 6))
      |> Enum.map(&assigned_entry/1)
      |> Enum.sort_by(&{&1.date, &1.slot})

    {%{
       assigned_count: length(entries),
       assigned_entries: entries,
       message: assigned_plan_message(entries, mode)
     }, acc}
  end

  def handle_tool("search_recipes", %{"query" => query}, acc),
    do: MealPlanCore.search_recipes_tool(query, acc)

  def handle_tool("search_ingredients", %{"query" => query}, acc),
    do: MealPlanCore.search_ingredients_tool(query, acc)

  def handle_tool("submit_plan", input, acc), do: MealPlanCore.submit_plan_tool(input, acc)

  def handle_tool(name, _input, acc), do: {%{error: "Unknown tool: #{name}"}, acc}

  # ── tool helpers ──────────────────────────────────────────────────────────────

  defp first_name(name) when is_binary(name) do
    name |> String.split() |> List.first() || "the client"
  end

  defp first_name(_), do: "the client"

  # The client's calendar meals for the plan week that land in one of the 5 slots.
  defp assigned_meals(client_id, first_day, end_date) do
    client_id
    |> History.list_calendar_user_meals(first_day, end_date)
    |> Enum.filter(&(MealType.label(&1.meal_type) in MealPlanCore.slots()))
  end

  defp assigned_entry(meal) do
    %{
      date: meal.start_dt |> NaiveDateTime.to_date() |> Date.to_string(),
      slot: MealType.label(meal.meal_type),
      items: assigned_items(meal)
    }
  end

  defp assigned_plan_message([], _mode),
    do: "No meals are on the calendar for the plan period — plan every slot."

  defp assigned_plan_message(_entries, :replace_week),
    do:
      "These meals will be REPLACED — plan every slot. Use the listed items only " <>
        "to avoid repeating them."

  defp assigned_plan_message(_entries, _fill_gaps),
    do:
      "These (date, slot) cells are already filled — do NOT plan them; plan only the empty cells."

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
end
