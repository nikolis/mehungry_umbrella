defmodule Mehungry.AI.MealPlanGenerator do
  @moduledoc """
  Generates a 7-day meal plan by asking the AI to assign meals (recipes and
  whole-food ingredients) from the user's library.

  Generation and persistence are separated:
    * `generate_entries/5` returns normalized, calendar-independent plan entries
      (see `MealPlanAgent.normalize_entry/2`) — used both by the calendar and by
      independent meal-blueprint plans.
    * `run/5` is the calendar convenience: generate, then create the `UserMeal`
      records directly, returning `{:ok, created, skipped}`.
    * `persist_entries_to_calendar/3` materializes entries onto calendar dates.
  """

  require Logger
  alias Mehungry.History
  alias Mehungry.History.MealType

  @model "claude-haiku-4-5-20251001"
  @max_recipes 80

  @doc """
  Calendar pipeline. Generates a plan and creates the `UserMeal` records on the
  calendar starting at `start_date`. Returns `{:ok, [%UserMeal{}], skipped}` or
  `{:error, reason}`.
  """
  def run(preferences, recipes, start_date, user_id, blueprint \\ nil) do
    case generate_entries(preferences, recipes, start_date, user_id, blueprint) do
      {:ok, entries} -> persist_entries_to_calendar(entries, user_id, start_date)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Produces normalized, calendar-independent plan entries. Delegates to
  `MealPlanAgent` (history-aware tool-use loop), falling back to the legacy
  single-shot pipeline if the agent errors. Returns `{:ok, entries}` or
  `{:error, reason}`.

  `blueprint` is an optional `%Mehungry.MealBlueprints.Blueprint{}` (or nil); its
  targets reach the planner through `preferences`.
  """
  def generate_entries(preferences, recipes, start_date, user_id, blueprint \\ nil) do
    case Mehungry.AI.Agents.MealPlanAgent.run(
           preferences,
           recipes,
           start_date,
           user_id,
           blueprint
         ) do
      {:ok, entries} ->
        {:ok, entries}

      {:error, reason} ->
        Logger.warning(
          "MealPlanAgent failed (#{inspect(reason)}), falling back to legacy pipeline"
        )

        generate_legacy_entries(preferences, recipes, start_date)
    end
  end

  @doc """
  Creates `UserMeal` calendar records from normalized `entries`, laying `day_index`
  1..7 onto `start_date`..`start_date+6`. Returns `{:ok, created, skipped}`.
  """
  def persist_entries_to_calendar(entries, user_id, start_date) do
    results = Enum.map(entries, &create_calendar_meal(&1, user_id, start_date))

    created = for {:ok, meal} <- results, do: meal
    skipped = Enum.count(results, &match?({:error, _}, &1))

    {:ok, created, skipped}
  end

  defp create_calendar_meal(entry, user_id, start_date) do
    date = Date.add(start_date, entry.day_index - 1)
    dt = NaiveDateTime.new!(date, MealType.slot_time(entry.meal_type))

    %{
      title: MealType.label(entry.meal_type),
      meal_type: entry.meal_type,
      start_dt: dt,
      user_id: user_id
    }
    |> Map.merge(item_attrs(entry))
    |> History.create_user_meal()
  end

  # Recipe entry → recipe_user_meals (consume_portions: 1 so the calendar's
  # nutrient summary, which scales by consume_portions / servings, shows real
  # numbers). Ingredient entry → ingredient_user_meals with the resolved unit FKs.
  defp item_attrs(%{recipe_id: recipe_id} = entry) when is_integer(recipe_id) do
    %{
      recipe_user_meals: [
        %{
          recipe_id: recipe_id,
          cooking_portions: entry.cooking_portions || 2,
          consume_portions: 1,
          cooking: true
        }
      ]
    }
  end

  defp item_attrs(%{ingredient_id: ingredient_id} = entry) when is_integer(ingredient_id) do
    %{
      ingredient_user_meals: [
        %{
          ingredient_id: ingredient_id,
          quantity: entry.quantity || 1.0,
          measurement_unit_id: entry.measurement_unit_id,
          ingredient_portion_id: entry.ingredient_portion_id
        }
      ]
    }
  end

  # Legacy single-shot pipeline: returns recipe-only normalized entries.
  defp generate_legacy_entries(preferences, recipes, start_date) do
    catalog = build_catalog(recipes)

    if catalog == [] do
      {:error, "No recipes found. Create some recipes first."}
    else
      with {:ok, plan} <- generate_plan(preferences, catalog, start_date) do
        {:ok, normalize_legacy_entries(plan, start_date)}
      end
    end
  end

  defp normalize_legacy_entries(plan, start_date) do
    plan
    |> Enum.filter(fn e ->
      is_binary(e["date"]) and is_binary(e["slot"]) and is_integer(e["recipe_id"])
    end)
    |> Enum.flat_map(fn e ->
      case Date.from_iso8601(e["date"]) do
        {:ok, date} ->
          [
            %{
              day_index: Date.diff(date, start_date) + 1,
              meal_type: MealType.from_slot(e["slot"]),
              recipe_id: e["recipe_id"],
              cooking_portions: e["cooking_portions"] || 2,
              ingredient_id: nil,
              quantity: nil,
              measurement_unit_id: nil,
              ingredient_portion_id: nil
            }
          ]

        _ ->
          []
      end
    end)
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

  # --- HTTP ---

  defp call_api(system, user) do
    case Mehungry.AI.Client.request(%{
           model: @model,
           system: system,
           messages: [%{role: "user", content: user}],
           max_tokens: 4096
         }) do
      {:ok, response} -> {:ok, Mehungry.AI.Client.text_from(response)}
      error -> error
    end
  end
end
