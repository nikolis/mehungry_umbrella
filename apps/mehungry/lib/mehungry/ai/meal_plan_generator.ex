defmodule Mehungry.AI.MealPlanGenerator do
  @moduledoc """
  Generation → persistence seam for AI meal plans.

    * `generate_entries/4` — a person's **own** plan, via `UserMealPlanAgent`.
      Returns normalized, calendar-independent entries. There is no fallback
      pipeline: when the agent fails, generation fails (an unguarded second
      attempt could not honour the diet / avoid guarantees).
    * `persist_entries_to_calendar/5` — writes entries (from **either** meal-plan
      agent) onto a user's calendar week in the chosen mode.
    * `run/5` — generate then persist, for the own-calendar case.

  ## Existing-meals modes

  When the target week already holds meals, the person who invoked the planner
  chooses what happens to them:

    * `:fill_gaps` (default) — every existing meal stays; an entry is written
      only where that `(date, meal slot)` cell is empty.
    * `:replace_week` — every meal in the 7-day span is deleted, then the plan
      is written, **in one transaction**: if any insert fails the whole thing
      rolls back and the week is left exactly as it was (`{:error,
      :replace_failed}`). Nothing is deleted when the plan has no entries.
  """

  alias Mehungry.History
  alias Mehungry.History.MealType
  alias Mehungry.AI.Agents.{MealPlanCore, UserMealPlanAgent}

  @modes [:fill_gaps, :replace_week]

  @doc "The existing-meals modes, as atoms."
  def modes, do: @modes

  @doc """
  Parses a mode from user/API input (`"fill_gaps"` / `"replace_week"`, or the
  atoms). Anything else → the non-destructive default `:fill_gaps`.
  """
  def parse_mode(mode) when mode in @modes, do: mode
  def parse_mode("replace_week"), do: :replace_week
  def parse_mode(_), do: :fill_gaps

  @doc """
  Own-calendar pipeline: generates a plan and writes it to `user_id`'s calendar
  starting at `start_date`. Returns `{:ok, [%UserMeal{}], skipped}` or
  `{:error, reason}`.
  """
  def run(preferences, start_date, user_id, blueprint \\ nil, mode \\ :fill_gaps) do
    case generate_entries(preferences, start_date, user_id, blueprint, mode: parse_mode(mode)) do
      {:ok, entries} -> persist_entries_to_calendar(entries, user_id, start_date, mode)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Produces normalized, calendar-independent plan entries for a person's own plan
  (`UserMealPlanAgent`). Returns `{:ok, entries}` or `{:error, reason}`.

  `blueprint` is an optional `%Mehungry.MealBlueprints.Blueprint{}` (or nil).
  `opts` are passed to the agent — `:mode` when the plan is headed for a calendar
  week (a `:replace_week` plan must cover every day's main meals).
  """
  def generate_entries(preferences, start_date, user_id, blueprint \\ nil, opts \\ []) do
    UserMealPlanAgent.run(preferences, start_date, user_id, blueprint, opts)
  end

  @doc """
  `generate_entries/5` with its report — `{:ok, %{entries:, calorie_warnings:,
  calorie_band:}}` — for callers that tell the person which days the plan could
  not bring inside their calorie range.
  """
  def generate_plan(preferences, start_date, user_id, blueprint \\ nil, opts \\ []) do
    UserMealPlanAgent.run_plan(preferences, start_date, user_id, blueprint, opts)
  end

  @doc """
  The `:from` a calendar plan for the week starting `start_date` passes: `today`
  when the week has begun and is not over yet (a person's past days hold what
  they actually ate, so a plan never rewrites them), else `nil` — a week wholly
  in the future or the past is planned in full.
  """
  def plan_from(%Date{} = start_date, today \\ Date.utc_today()) do
    if Date.compare(today, start_date) == :gt and
         Date.compare(today, Date.add(start_date, 6)) != :gt,
       do: today
  end

  @doc """
  How many meals `user_id` already has in the plan week (`start_date` + 6 days),
  counting from `from` — what a caller checks to decide whether to ask for an
  existing-meals mode.
  """
  def existing_meal_count(user_id, %Date{} = start_date, from \\ nil) do
    History.count_user_meals_in_date_range(
      user_id,
      first_day(start_date, from),
      Date.add(start_date, 6)
    )
  end

  @doc """
  Creates `UserMeal` calendar records from normalized `entries`, laying
  `day_index` 1..7 onto `start_date`..`start_date+6`, honouring `mode` (see the
  moduledoc). One entry is one meal: all of its items (a main recipe, a salad, a
  dessert, fruit, nuts…) land on the same `UserMeal`. The older one-item flat entry
  is accepted too (`MealPlanCore.entry_items/1`). Returns `{:ok, created, skipped}` — `skipped` counts entries whose
  insert failed (entries dropped because their cell was taken are not failures) —
  or, for `:replace_week`, `{:error, :replace_failed}` when the swap was rolled
  back.

  Options:
    * `:from` — a `%Date{}` inside the week; days before it are left untouched
      (no entry is written there and `:replace_week` does not delete there). A
      nutritionist's draft passes today, so a client's past days — what they
      actually ate — are never rewritten.
  """
  def persist_entries_to_calendar(entries, user_id, start_date, mode \\ :fill_gaps, opts \\ []) do
    from = first_day(start_date, Keyword.get(opts, :from))

    entries =
      Enum.reject(entries, &(Date.compare(Date.add(start_date, &1.day_index - 1), from) == :lt))

    entries
    |> write_week(user_id, start_date, from, parse_mode(mode))
    |> tap(&poke_clients(&1, user_id))
  end

  # The plan was written by a background job (often a nutritionist's draft for
  # someone else): poke that person's connected clients so an open calendar
  # refetches instead of showing the old week until the app is restarted.
  defp poke_clients({:ok, [_ | _], _skipped}, user_id),
    do: History.broadcast_meals_changed(user_id)

  defp poke_clients(_result, _user_id), do: :ok

  defp write_week([], _user_id, _start_date, _from, _mode), do: {:ok, [], 0}

  # :replace_week — delete + insert as one unit, so a failed insert can never
  # leave the week emptied.
  defp write_week(entries, user_id, start_date, from, :replace_week) do
    Mehungry.Repo.transaction(fn ->
      History.delete_user_meals_in_date_range(user_id, from, Date.add(start_date, 6))

      Enum.map(entries, fn entry ->
        case create_calendar_meal(entry, user_id, start_date) do
          {:ok, meal} -> meal
          {:error, _} -> Mehungry.Repo.rollback(:replace_failed)
        end
      end)
    end)
    |> case do
      {:ok, created} -> {:ok, created, 0}
      {:error, _} -> {:error, :replace_failed}
    end
  end

  defp write_week(entries, user_id, start_date, from, :fill_gaps) do
    results =
      entries
      |> prepare_week(user_id, start_date, from, :fill_gaps)
      |> Enum.map(&create_calendar_meal(&1, user_id, start_date))

    created = for {:ok, meal} <- results, do: meal
    skipped = Enum.count(results, &match?({:error, _}, &1))

    {:ok, created, skipped}
  end

  # The first day a plan may touch: `from` when it falls later than the week start.
  defp first_day(start_date, %Date{} = from) do
    if Date.compare(from, start_date) == :gt, do: from, else: start_date
  end

  defp first_day(start_date, _from), do: start_date

  # :fill_gaps — drop every entry whose (day, meal type) cell already has a meal.
  # Computed here from the calendar itself, so it holds no matter what the model
  # was (or was not) told about the week.
  defp prepare_week(entries, user_id, start_date, _from, :fill_gaps) do
    occupied =
      user_id
      |> History.list_calendar_user_meals(start_date, Date.add(start_date, 6))
      |> Enum.reject(&is_nil(&1.meal_type))
      |> MapSet.new(fn meal ->
        {Date.diff(NaiveDateTime.to_date(meal.start_dt), start_date) + 1, meal.meal_type}
      end)

    Enum.reject(entries, &MapSet.member?(occupied, {&1.day_index, &1.meal_type}))
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
    |> Map.merge(items_attrs(MealPlanCore.entry_items(entry)))
    |> History.create_user_meal()
  end

  # A leftover item eats what that day's Lunch cooked: `cooking: false` and no
  # cooking portions (the shopping list reads cooking_portions, and the Lunch row
  # was already raised to cover it — `MealPlanCore.normalize_entries/3`), while
  # `consume_portions` makes the calendar count its calories.
  defp recipe_user_meal_attrs(%{leftover: true} = item) do
    %{
      recipe_id: item.recipe_id,
      cooking_portions: 0,
      consume_portions: Map.get(item, :servings) || 1,
      cooking: false
    }
  end

  defp recipe_user_meal_attrs(item) do
    servings = Map.get(item, :servings) || 1

    %{
      recipe_id: item.recipe_id,
      cooking_portions: max(Map.get(item, :cooking_portions) || 2, servings),
      consume_portions: servings,
      cooking: true
    }
  end

  # Recipe items → recipe_user_meals, ingredient items → ingredient_user_meals.
  # `consume_portions` is the servings the plan has the person eat at that meal (1
  # unless the agent scaled it to reach the calorie band) — the calendar's nutrient
  # summary scales by consume_portions / servings. You can't eat more than was
  # cooked, so cooking_portions is raised to match.
  defp items_attrs(items) do
    {recipes, ingredients} = Enum.split_with(items, &is_integer(Map.get(&1, :recipe_id)))

    %{
      recipe_user_meals: Enum.map(recipes, &recipe_user_meal_attrs/1),
      ingredient_user_meals:
        Enum.map(ingredients, fn item ->
          %{
            ingredient_id: item.ingredient_id,
            quantity: Map.get(item, :quantity) || 1.0,
            measurement_unit_id: Map.get(item, :measurement_unit_id),
            ingredient_portion_id: Map.get(item, :ingredient_portion_id)
          }
        end)
    }
  end
end
