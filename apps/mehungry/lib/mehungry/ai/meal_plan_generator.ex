defmodule Mehungry.AI.MealPlanGenerator do
  @moduledoc """
  Generates a 7-day meal plan by asking the AI to assign meals from the user's
  actual recipe library, then creates the resulting UserMeal records directly.
  """

  require Logger
  alias Mehungry.History

  @api_url "https://api.anthropic.com/v1/messages"
  @model "claude-haiku-4-5-20251001"
  @timeout_ms 60_000
  @max_recipes 80

  @doc """
  Full pipeline. Returns {:ok, [%UserMeal{}], count} or {:error, reason}.
  recipes: preloaded list already available in the LiveView assigns.
  """
  def run(preferences, recipes, start_date, user_id) do
    catalog = build_catalog(recipes)

    if catalog == [] do
      {:error, "No recipes found. Create some recipes first."}
    else
      with {:ok, plan} <- generate_plan(preferences, catalog, start_date),
           {:ok, created, skipped} <- create_user_meals(plan, user_id) do
        {:ok, created, skipped}
      end
    end
  end

  # --- Catalog ---

  defp build_catalog(recipes) do
    recipes
    |> Enum.take(@max_recipes)
    |> Enum.map(fn r ->
      %{id: r.id, title: r.title, servings: r.servings || 2, difficulty: r.difficulty || 1}
    end)
  end

  # --- Phase 1: AI call ---

  defp generate_plan(preferences, catalog, start_date) do
    system = """
    You are a meal planner. Generate a 7-day meal plan as valid JSON.
    Use ONLY recipe_ids from the provided catalog. Return only a valid JSON array, no markdown, no explanation.
    """

    user = build_prompt(preferences, catalog, start_date)

    case call_api(system, user) do
      {:ok, text} ->
        text
        |> String.trim()
        |> String.replace(~r/```json\s*/i, "")
        |> String.replace(~r/```\s*/, "")
        |> String.trim()
        |> Jason.decode()
        |> case do
          {:ok, entries} when is_list(entries) -> {:ok, entries}
          _ -> {:error, "Could not parse meal plan from AI response"}
        end

      error ->
        error
    end
  end

  defp build_prompt(preferences, catalog, start_date) do
    end_date = Date.add(start_date, 6)

    catalog_text =
      Enum.map_join(catalog, "\n", fn r ->
        "  recipe_id:#{r.id} \"#{r.title}\" (servings:#{r.servings}, difficulty:#{r.difficulty})"
      end)

    """
    User preferences: "#{preferences}"

    Plan meals from #{Date.to_string(start_date)} to #{Date.to_string(end_date)} (7 days).
    Meal slots per day: Breakfast, Lunch, Dinner.

    Available recipes (use ONLY these recipe_ids):
    #{catalog_text}

    Return a JSON array of exactly 21 entries (3 per day × 7 days):
    [
      {"date": "YYYY-MM-DD", "slot": "Breakfast", "recipe_id": integer, "cooking_portions": integer},
      ...
    ]

    Rules:
    - Vary recipes across the week — minimize repetition
    - cooking_portions should be 1–4 based on recipe servings and user preferences
    - Match recipe types to meal slots (lighter meals for breakfast, heartier for dinner)
    - Use exact date strings in YYYY-MM-DD format
    - Only use Breakfast, Lunch, or Dinner as slot values
    """
  end

  # --- Phase 2: create UserMeal records ---

  defp create_user_meals(plan, user_id) do
    results =
      plan
      |> Enum.filter(fn entry ->
        is_binary(entry["date"]) and
          is_binary(entry["slot"]) and
          is_integer(entry["recipe_id"])
      end)
      |> Enum.map(fn entry -> attempt_create(entry, user_id) end)

    created = Enum.flat_map(results, fn
      {:ok, meal} -> [meal]
      _ -> []
    end)

    skipped = Enum.count(results, fn
      {:error, _} -> true
      _ -> false
    end)

    {:ok, created, skipped}
  end

  defp attempt_create(entry, user_id) do
    case build_datetime(entry["date"], entry["slot"]) do
      {:ok, dt} ->
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

      :error ->
        Logger.warning("MealPlanGenerator: invalid date #{inspect(entry["date"])}")
        {:error, :invalid_date}
    end
  end

  defp build_datetime(date_str, slot) do
    with {:ok, date} <- Date.from_iso8601(date_str),
         {:ok, dt} <- NaiveDateTime.new(date, slot_time(slot)) do
      {:ok, dt}
    else
      _ -> :error
    end
  end

  defp slot_time("Breakfast"), do: ~T[08:00:00]
  defp slot_time("Lunch"), do: ~T[13:00:00]
  defp slot_time("Dinner"), do: ~T[19:00:00]
  defp slot_time(_), do: ~T[12:00:00]

  # --- HTTP ---

  defp call_api(system, user) do
    api_key = Application.get_env(:mehungry, :anthropic_api_key, "")

    if api_key == "" do
      {:error, "ANTHROPIC_API_KEY is not configured"}
    else
      do_call(api_key, system, user)
    end
  end

  defp do_call(api_key, system, user) do
    body =
      Jason.encode!(%{
        model: @model,
        max_tokens: 4096,
        system: system,
        messages: [%{role: "user", content: user}]
      })

    headers = [
      {"Content-Type", "application/json"},
      {"x-api-key", api_key},
      {"anthropic-version", "2023-06-01"}
    ]

    case HTTPoison.post(@api_url, body, headers, recv_timeout: @timeout_ms) do
      {:ok, %HTTPoison.Response{status_code: 200, body: resp_body}} ->
        case Jason.decode(resp_body) do
          {:ok, %{"content" => [%{"text" => text} | _]}} ->
            {:ok, text}

          {:ok, resp} ->
            Logger.warning("Unexpected Anthropic response: #{inspect(resp)}")
            {:error, "Unexpected API response format"}
        end

      {:ok, %HTTPoison.Response{status_code: code, body: body}} ->
        Logger.warning("Anthropic API #{code}: #{body}")
        {:error, "API returned status #{code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.warning("Anthropic HTTP error: #{inspect(reason)}")
        {:error, "HTTP request failed: #{inspect(reason)}"}
    end
  end
end
