defmodule Mehungry.AI.Agents.MealPlanAgent do
  @moduledoc """
  History-aware meal plan generation agent built on the AI.Agent tool-use loop.

  Replaces the single-shot prompt in MealPlanGenerator with a loop that:
    1. Reads the user's recent meal history to avoid repetition
    2. Queries the recipe catalog by keyword / slot type
    3. Submits the complete 7-day plan for validation before creating records

  If submit_plan returns errors (invalid recipe_id, duplicate slot, out-of-range
  date) the AI corrects and resubmits automatically.

  Returns the same {:ok, [%UserMeal{}], skipped_count} tuple as MealPlanGenerator.run/4.
  """

  require Logger
  alias Mehungry.{History, AI.Agent, Search.RecipeVectorSearch}

  @model "claude-haiku-4-5-20251001"
  @history_days 21

  @doc """
  Generates and persists a 7-day meal plan for `user_id` starting at `start_date`.

  - `preferences` — free-text dietary preferences from the user
  - `recipes`     — list of recipe structs already loaded in the LiveView
  - `start_date`  — %Date{} for the first day of the plan
  - `user_id`     — integer

  Returns {:ok, [%UserMeal{}], skipped_count} or {:error, reason}.
  """
  def run(preferences, _recipes, start_date, user_id) do
    Process.put(__MODULE__, nil)

    context = %{
      user_id: user_id,
      start_date: start_date
    }

    result =
      Agent.run(
        system_prompt(preferences, start_date),
        initial_message(preferences, start_date),
        tool_defs(),
        &handle_tool/3,
        context,
        model: @model,
        max_tokens: 4096,
        max_iterations: 12
      )

    case result do
      {:ok, _text} ->
        case Process.get(__MODULE__) do
          nil -> {:error, "Agent completed without submitting a plan"}
          saved -> saved
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ── system prompt ─────────────────────────────────────────────────────────────

  defp system_prompt(preferences, start_date) do
    end_date = Date.add(start_date, 6)

    """
    You are a personal meal planner creating a 7-day plan.

    Plan period: #{Date.to_string(start_date)} to #{Date.to_string(end_date)} (inclusive).
    Meal slots each day: Breakfast, Lunch, Dinner (21 total entries).
    User preferences: #{preferences}

    WORKFLOW:
    1. Call get_recent_meals to see what the user has eaten lately — avoid heavy repetition
    2. Call search_catalog to find recipes suitable for each slot type:
       - Breakfast: light, quick meals
       - Lunch: moderate meals
       - Dinner: hearty, more complex meals
       You may call search_catalog multiple times with different queries
    3. Draft the 21-entry plan using ONLY recipe_ids from your search results
    4. Call submit_plan with the complete plan
    5. If submit_plan returns errors, fix the reported issues and resubmit

    RULES:
    - Use ONLY recipe_ids returned by search_catalog — never invent IDs
    - Vary recipes across the week — no recipe should appear more than twice
    - cooking_portions: 1–4 based on recipe servings
    - Use exact date strings in YYYY-MM-DD format
    - Slot values must be exactly: Breakfast, Lunch, or Dinner
    - submit_plan is the ONLY way to complete the task
    """
  end

  defp initial_message(preferences, start_date) do
    "Create a 7-day meal plan starting #{Date.to_string(start_date)} with these preferences: #{preferences}"
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
        name: "submit_plan",
        description:
          "Validate and persist the completed 7-day meal plan. " <>
            "Pass all 21 entries at once. Returns success with created meal count, " <>
            "or a list of errors to fix before resubmitting.",
        input_schema: %{
          type: "object",
          properties: %{
            entries: %{
              type: "array",
              description: "List of exactly 21 meal entries",
              items: %{
                type: "object",
                properties: %{
                  date: %{type: "string", description: "YYYY-MM-DD"},
                  slot: %{type: "string", description: "Breakfast, Lunch, or Dinner"},
                  recipe_id: %{type: "integer"},
                  cooking_portions: %{type: "integer", description: "1–4"}
                },
                required: ["date", "slot", "recipe_id", "cooking_portions"]
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

  defp handle_tool("get_recent_meals", _input, %{user_id: user_id, start_date: start_date}) do
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

    if entries == [] do
      %{history: [], message: "No recent meal history found."}
    else
      %{history: entries, count: length(entries)}
    end
  end

  defp handle_tool("search_catalog", %{"query" => query}, %{user_id: user_id}) do
    recipes =
      RecipeVectorSearch.search(query, user_id: user_id, limit: 20)
      |> Enum.map(fn r ->
        %{id: r.id, title: r.title, difficulty: r.difficulty || 1, servings: r.servings || 2}
      end)

    if recipes == [] do
      %{found: false, message: "No recipes found for '#{query}'. Try a different query."}
    else
      %{found: true, count: length(recipes), recipes: recipes}
    end
  end

  defp handle_tool("submit_plan", %{"entries" => entries} = input, context) do
    %{user_id: user_id, start_date: start_date} = context
    valid_ids = Mehungry.Food.list_user_recipes(user_id) |> MapSet.new(& &1.id)
    end_date = Date.add(start_date, 6)

    errors = validate_plan(entries, valid_ids, start_date, end_date)

    if errors == [] do
      {created, skipped} = persist_plan(entries, user_id)
      rationale = Map.get(input, "rationale", "")
      Process.put(__MODULE__, {:ok, created, skipped})

      Logger.info(
        "MealPlanAgent: plan submitted — #{length(created)} created, #{skipped} skipped. #{rationale}"
      )

      %{
        success: true,
        created: length(created),
        skipped: skipped,
        message: "Plan saved successfully."
      }
    else
      Logger.warning("MealPlanAgent: submit_plan errors: #{inspect(errors)}")
      %{success: false, errors: errors}
    end
  end

  defp handle_tool(name, _input, _ctx) do
    %{error: "Unknown tool: #{name}"}
  end

  # ── plan validation ───────────────────────────────────────────────────────────

  defp validate_plan(entries, valid_ids, start_date, end_date) do
    slot_errors = check_duplicate_slots(entries)
    entry_errors = Enum.flat_map(entries, &validate_entry(&1, valid_ids, start_date, end_date))
    slot_errors ++ entry_errors
  end

  defp check_duplicate_slots(entries) do
    duplicates =
      entries
      |> Enum.group_by(fn e -> {e["date"], e["slot"]} end)
      |> Enum.filter(fn {_key, group} -> length(group) > 1 end)
      |> Enum.map(fn {{date, slot}, _} -> "Duplicate slot: #{date} #{slot}" end)

    duplicates
  end

  defp validate_entry(entry, valid_ids, start_date, end_date) do
    errors = []

    errors =
      case Date.from_iso8601(entry["date"] || "") do
        {:ok, date} ->
          if Date.compare(date, start_date) in [:gt, :eq] and
               Date.compare(date, end_date) in [:lt, :eq] do
            errors
          else
            ["Date #{entry["date"]} is outside the plan range #{start_date} – #{end_date}" | errors]
          end

        _ ->
          ["Invalid date format '#{entry["date"]}' — use YYYY-MM-DD" | errors]
      end

    errors =
      if entry["slot"] in ["Breakfast", "Lunch", "Dinner"] do
        errors
      else
        ["Invalid slot '#{entry["slot"]}' — must be Breakfast, Lunch, or Dinner" | errors]
      end

    errors =
      case entry["recipe_id"] do
        id when is_integer(id) ->
          if MapSet.member?(valid_ids, id) do
            errors
          else
            ["recipe_id #{id} is not in the catalog — use search_catalog to find valid IDs" | errors]
          end

        _ ->
          ["Missing or non-integer recipe_id in entry #{inspect(entry)}" | errors]
      end

    errors
  end

  # ── record creation ───────────────────────────────────────────────────────────

  defp persist_plan(entries, user_id) do
    results =
      entries
      |> Enum.filter(fn e ->
        is_binary(e["date"]) and e["slot"] in ["Breakfast", "Lunch", "Dinner"] and
          is_integer(e["recipe_id"])
      end)
      |> Enum.map(&attempt_create(&1, user_id))

    created = Enum.flat_map(results, fn
      {:ok, meal} -> [meal]
      _ -> []
    end)

    skipped = Enum.count(results, fn
      {:error, _} -> true
      _ -> false
    end)

    {created, skipped}
  end

  defp attempt_create(entry, user_id) do
    with {:ok, date} <- Date.from_iso8601(entry["date"]),
         {:ok, dt} <- NaiveDateTime.new(date, slot_time(entry["slot"])) do
      attrs = %{
        title: entry["slot"],
        start_dt: dt,
        user_id: user_id,
        recipe_user_meals: [
          %{
            recipe_id: entry["recipe_id"],
            cooking_portions: entry["cooking_portions"] || 2,
            consume_portions: 0,
            cooking: true
          }
        ]
      }

      History.create_user_meal(attrs)
    else
      _ ->
        Logger.warning("MealPlanAgent: could not parse date for entry #{inspect(entry)}")
        {:error, :invalid_entry}
    end
  end

  defp slot_time("Breakfast"), do: ~T[08:00:00]
  defp slot_time("Lunch"), do: ~T[13:00:00]
  defp slot_time("Dinner"), do: ~T[19:00:00]
  defp slot_time(_), do: ~T[12:00:00]

end
