defmodule MehungryWeb.WeeklyPlanGraphicGenerator do
  @moduledoc """
  Turns a user's calendar week into a persisted, shareable weekly-plan card in one
  call: build the truthful week data → render (`WeeklyPlanGraphic`) → upload
  (`Storage`) → persist (`Food.create_weekly_plan_graphic/1`).

  No AI and no quota — the card is deterministic. The caller (the calendar
  LiveView) passes the **already-loaded, formatted** week meals (`@user_meals`) so
  the card is drawn from the exact data the calendar shows; nothing is re-queried
  or re-derived. Macro numbers come from `Mehungry.NutrientUtils.macro_summary/1`,
  the same function the calendar's day/week headers use.

  Always returns `{:ok, graphic} | {:error, reason}` — every exception is caught
  and turned into `{:error, message}` so callers never hang on a crash.
  """

  require Logger

  alias Mehungry.{Food, NutrientUtils, Storage}
  alias Mehungry.History.MealType
  alias MehungryWeb.CalendarLive.Calendar.Locale
  alias MehungryWeb.WeeklyPlanGraphic

  @doc """
  `week_meals` is the formatted list from `History.format_user_meals/1` for the
  week (each item has `:start_dt`, `:meal_type`, and the `*_user_meals` lists).
  `opts`: `:goal_label`, `:locale`, `:share_url`.
  """
  @spec generate(struct(), Date.t(), list(), keyword()) :: {:ok, struct()} | {:error, term()}
  def generate(user, %Date{} = week_start, week_meals, opts \\ []) do
    case build_week_data(week_start, week_meals, opts) do
      {:error, reason} ->
        {:error, reason}

      {:ok, %{week_data: week_data, summary: summary, caption: caption, locale: locale, goal_label: goal_label}} ->
        with {:ok, binary} <- WeeklyPlanGraphic.render(week_data),
             key =
               "weekly_plan_graphics/#{user.id}-#{Date.to_iso8601(week_start)}-#{System.system_time(:second)}.png",
             {:ok, %{url: url}} <- Storage.put(key, binary, content_type: "image/png"),
             {:ok, graphic} <-
               Food.create_weekly_plan_graphic(%{
                 user_id: user.id,
                 week_start: week_start,
                 locale: locale,
                 goal_label: goal_label,
                 image_url: url,
                 macros: summary,
                 caption: caption
               }) do
          {:ok, graphic}
        else
          {:error, reason} -> {:error, reason}
          other -> {:error, other}
        end
    end
  rescue
    e ->
      Logger.error("WeeklyPlanGraphicGenerator: #{Exception.message(e)}")
      {:error, Exception.message(e)}
  end

  @doc """
  Pure data step (no render, no Storage): turns the week's formatted meals into the
  `WeeklyPlanGraphic.render/1` input plus the macro summary and caption persisted
  on the graphic row. Returns `{:error, :empty_week}` when the week has no meals.
  """
  @spec build_week_data(Date.t(), list(), keyword()) ::
          {:ok, map()} | {:error, :empty_week}
  def build_week_data(%Date{} = week_start, week_meals, opts \\ []) do
    week_meals = Enum.filter(week_meals, &in_week?(&1, week_start))

    if week_meals == [] do
      {:error, :empty_week}
    else
      goal_label = opts[:goal_label]
      locale = opts[:locale] || "en"
      share_url = opts[:share_url] || "m3hungry.com"

      # Week totals → daily averages (÷7), exactly as the calendar's weekly
      # summary does, then the shared macro summary.
      daily_avg =
        week_meals
        |> NutrientUtils.summarize_meals_nutrients()
        |> NutrientUtils.scale_nutrient_map(1 / 7)

      summary = NutrientUtils.macro_summary(daily_avg)

      macros = %{
        protein_g: summary.protein_g,
        carbs_g: summary.carbs_g,
        fat_g: summary.fat_g,
        calories: summary.energy_kcal
      }

      week_data = %{
        range_label: range_label(week_start, locale),
        goal_label: goal_label,
        days: build_days(week_meals, week_start, locale),
        macros: macros,
        share_url: share_url,
        locale: locale
      }

      {:ok,
       %{
         week_data: week_data,
         summary: summary,
         caption: caption(summary, goal_label),
         locale: locale,
         goal_label: goal_label
       }}
    end
  end

  @doc """
  The default post title for a generated card (used by `create_weekly_plan_post`).
  """
  def post_title(%{week_start: week_start, goal_label: goal_label} = graphic) do
    range = range_label(week_start, Map.get(graphic, :locale) || "en")
    if goal_label in [nil, ""], do: "My week · #{range}", else: "#{goal_label} week · #{range}"
  end

  defp in_week?(meal, week_start) do
    case Map.get(meal, :start_dt) do
      %NaiveDateTime{} = dt ->
        d = NaiveDateTime.to_date(dt)
        Date.compare(d, week_start) != :lt and Date.compare(d, Date.add(week_start, 6)) != :gt

      _ ->
        false
    end
  end

  # One row per calendar day (Mon..Sun), each with its localized short day label
  # and ordered meal titles (slot tags localized for `locale`).
  defp build_days(week_meals, week_start, locale) do
    by_date =
      Enum.group_by(week_meals, fn m -> NaiveDateTime.to_date(m.start_dt) end)

    Enum.map(0..6, fn offset ->
      date = Date.add(week_start, offset)
      meals = Map.get(by_date, date, [])

      %{
        label: Locale.day_short(date, locale),
        meals: titles_for_day(meals, locale)
      }
    end)
  end

  # One line per meal *slot* for a day, as `%{tag, title}`, ordered by meal type
  # (breakfast → dinner, unsorted last). A slot's items (recipe / ingredient /
  # free-food, possibly several) are joined into a single title, so a full day is
  # at most 6 lines (5 slots + unsorted) — bounded regardless of how many items
  # each slot holds. `tag` is the meal-type label ("Breakfast"…) or nil for the
  # unsorted bucket.
  defp titles_for_day(meals, locale) do
    by_type = Enum.group_by(meals, fn m -> Map.get(m, :meal_type) end)

    for meal_type <- MealType.ordered() ++ [nil],
        group = Map.get(by_type, meal_type, []),
        group != [],
        titles = Enum.flat_map(group, &meal_titles/1),
        titles != [] do
      %{tag: tag_for(meal_type, locale), title: Enum.join(titles, ", ")}
    end
  end

  defp tag_for(nil, _locale), do: nil
  defp tag_for(meal_type, locale), do: MehungryWeb.MealTypeLabels.label(meal_type, locale)

  defp meal_titles(meal) do
    recipe = Enum.map(Map.get(meal, :recipe_user_meals, []), & &1.title)
    ingredient = Enum.map(Map.get(meal, :ingredient_user_meals, []), & &1.title)
    free = Enum.map(Map.get(meal, :free_food_user_meals, []), & &1.title)

    (recipe ++ ingredient ++ free)
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
  end

  # "6 Oct – 12 Oct" (en) / "6 Οκτ – 12 Οκτ" (el).
  defp range_label(week_start, locale \\ "en") do
    "#{short_date(week_start, locale)} – #{short_date(Date.add(week_start, 6), locale)}"
  end

  defp short_date(date, locale) do
    "#{date.day} #{Locale.month_short(date, locale)}"
  end

  defp caption(summary, goal_label) do
    lead = if goal_label in [nil, ""], do: "A planned week", else: "#{goal_label} week"

    "#{lead} · ~#{summary.energy_kcal} kcal/day · #{round(summary.protein_g)} g protein avg"
  end
end
