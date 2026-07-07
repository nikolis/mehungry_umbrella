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
  alias Mehungry.{Food, History, Professionals, AI.Agent, Search.RecipeVectorSearch}

  @model "claude-haiku-4-5-20251001"
  @history_days 21

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
    Process.put(__MODULE__, nil)

    ctx = %{
      professional_id: professional_id,
      client_id: client_id,
      start_date: Date.utc_today()
    }

    handler = fn name, input, ctx ->
      on_event.({:tool_call, name})
      result = do_handle_tool(name, input, ctx)
      on_event.({:tool_result, name, result})
      result
    end

    result =
      Agent.run(
        system_prompt(preferences, ctx.start_date),
        "Draft a 7-day meal plan for this client. Preferences: #{preferences}",
        tool_defs(),
        handler,
        ctx,
        model: @model,
        max_tokens: 4096,
        max_iterations: 16
      )

    case result do
      {:ok, summary} ->
        case Process.get(__MODULE__) do
          nil -> {:ok, summary}
          {:plan_created, count} -> {:ok, "#{summary}\n\n✓ #{count} meal entries created."}
        end

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
    Client preferences / notes: #{preferences}

    WORKFLOW:
    1. Call get_client_summary to understand the client's recent activity
    2. Call get_recent_meals to see what the client has eaten lately (avoid repetition)
    3. Call get_ratings to understand which types of meals the client rated well or poorly
    4. Call search_recipes one or more times to find suitable meals for each slot type
    5. Draft the 21-entry plan (3 meals/day × 7 days: Breakfast, Lunch, Dinner)
    6. Call submit_plan with the entries and a 2–3 sentence professional rationale
    7. If submit_plan returns errors, fix them and resubmit

    RULES:
    - Only use recipe_ids returned by search_recipes — never invent IDs
    - Vary recipes to minimise repetition, especially for recipes seen in recent history
    - Match recipe difficulty and type to the slot (lighter for Breakfast)
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
        name: "search_recipes",
        description:
          "Semantically search the professional's recipe catalog. " <>
            "Returns recipe_id, title, difficulty (1–3), and servings. " <>
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
        name: "submit_plan",
        description:
          "Validate and persist the 7-day meal plan for the client. " <>
            "Returns success with a count of created entries, or errors to fix.",
        input_schema: %{
          type: "object",
          properties: %{
            entries: %{
              type: "array",
              description: "21 meal entries covering 7 days × 3 slots",
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

  defp do_handle_tool("get_client_summary", _input, %{
         client_id: client_id,
         start_date: start_date
       }) do
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

    %{
      name: client.name || client.email,
      email: client.email,
      recent_meal_count: length(recent_meals),
      rating_count: length(ratings),
      avg_rating: avg_rating
    }
  end

  defp do_handle_tool("get_recent_meals", _input, %{client_id: client_id, start_date: start_date}) do
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

    %{recent_meals: entries, count: length(entries)}
  end

  defp do_handle_tool("get_ratings", _input, %{client_id: client_id}) do
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

    %{ratings: entries, count: length(entries)}
  end

  defp do_handle_tool("search_recipes", %{"query" => query}, %{professional_id: professional_id}) do
    recipes =
      RecipeVectorSearch.search(query, user_id: professional_id, limit: 20)
      |> Enum.map(fn r ->
        %{
          recipe_id: r.id,
          title: r.title,
          difficulty: r.difficulty || 1,
          servings: r.servings || 2
        }
      end)

    if recipes == [] do
      %{found: false, message: "No recipes found for '#{query}'. Try a different query."}
    else
      %{found: true, count: length(recipes), recipes: recipes}
    end
  end

  defp do_handle_tool("submit_plan", %{"entries" => entries, "rationale" => rationale}, context) do
    %{client_id: client_id, start_date: start_date, professional_id: professional_id} = context

    valid_ids =
      Food.list_user_recipes(professional_id)
      |> MapSet.new(& &1.id)

    end_date = Date.add(start_date, 6)
    errors = validate_entries(entries, valid_ids, start_date, end_date)

    if errors == [] do
      {created, skipped} = persist_entries(entries, client_id)
      Process.put(__MODULE__, {:plan_created, length(created)})

      Logger.info(
        "NutritionistAgent: plan created — #{length(created)} meals for client #{client_id}. #{rationale}"
      )

      %{
        success: true,
        created: length(created),
        skipped: skipped,
        rationale: rationale,
        message: "Plan created successfully."
      }
    else
      %{success: false, errors: errors}
    end
  end

  defp do_handle_tool(name, _input, _ctx) do
    %{error: "Unknown tool: #{name}"}
  end

  # ── plan validation ───────────────────────────────────────────────────────────

  defp validate_entries(entries, valid_ids, start_date, end_date) do
    duplicate_errors =
      entries
      |> Enum.group_by(fn e -> {e["date"], e["slot"]} end)
      |> Enum.filter(fn {_, g} -> length(g) > 1 end)
      |> Enum.map(fn {{date, slot}, _} -> "Duplicate: #{date} #{slot}" end)

    entry_errors = Enum.flat_map(entries, &validate_entry(&1, valid_ids, start_date, end_date))

    duplicate_errors ++ entry_errors
  end

  defp validate_entry(entry, valid_ids, start_date, end_date) do
    errors = []

    errors =
      case Date.from_iso8601(entry["date"] || "") do
        {:ok, d} when d >= start_date and d <= end_date -> errors
        {:ok, d} -> ["Date #{d} is outside the plan window #{start_date}–#{end_date}" | errors]
        _ -> ["Invalid date '#{entry["date"]}'" | errors]
      end

    errors =
      if entry["slot"] in ["Breakfast", "Lunch", "Dinner"],
        do: errors,
        else: ["Invalid slot '#{entry["slot"]}'" | errors]

    errors =
      case entry["recipe_id"] do
        id when is_integer(id) and id > 0 ->
          if MapSet.member?(valid_ids, id),
            do: errors,
            else: ["recipe_id #{id} not in your catalog — use search_recipes" | errors]

        _ ->
          ["Missing or invalid recipe_id" | errors]
      end

    errors
  end

  # ── record creation ───────────────────────────────────────────────────────────

  defp persist_entries(entries, client_id) do
    results =
      entries
      |> Enum.filter(fn e ->
        is_binary(e["date"]) and e["slot"] in ["Breakfast", "Lunch", "Dinner"] and
          is_integer(e["recipe_id"])
      end)
      |> Enum.map(&create_user_meal(&1, client_id))

    created =
      Enum.flat_map(results, fn
        {:ok, m} -> [m]
        _ -> []
      end)

    skipped =
      Enum.count(results, fn
        {:error, _} -> true
        _ -> false
      end)

    {created, skipped}
  end

  defp create_user_meal(entry, client_id) do
    with {:ok, date} <- Date.from_iso8601(entry["date"]),
         {:ok, dt} <- NaiveDateTime.new(date, slot_time(entry["slot"])) do
      History.create_user_meal(%{
        title: entry["slot"],
        start_dt: dt,
        user_id: client_id,
        recipe_user_meals: [
          %{
            recipe_id: entry["recipe_id"],
            cooking_portions: entry["cooking_portions"] || 2,
            consume_portions: 0,
            cooking: true
          }
        ]
      })
    else
      _ -> {:error, :invalid_entry}
    end
  end

  defp slot_time("Breakfast"), do: ~T[08:00:00]
  defp slot_time("Lunch"), do: ~T[13:00:00]
  defp slot_time("Dinner"), do: ~T[19:00:00]
  defp slot_time(_), do: ~T[12:00:00]
end
