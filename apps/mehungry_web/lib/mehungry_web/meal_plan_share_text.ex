defmodule MehungryWeb.MealPlanShareText do
  @moduledoc """
  Deterministic, copy-ready social captions for a published meal plan
  (`/meal-plans/:slug`).

  These are the ready-to-paste share units for **external** platforms — the
  user downloads the PNG card and/or copies one of these text blocks into
  Instagram / Pinterest / Facebook / X / Threads / WhatsApp. Everything is built
  purely from the immutable plan snapshot (`Mehungry.PublishedPlans`) — no DB, no
  IO — so the same captions render in the synchronous (crawler) page render.

  The macro numbers come straight from `plan.macros` (the daily-average summary
  produced by `Mehungry.NutrientUtils.macro_summary/1`) and are formatted exactly
  as the page's `<.macro_tile>` grid shows them, so the caption can never drift
  from what the viewer reads on the page.

  Two formats:

    * `image_caption/2` — short caption to pair with the shareable PNG card.
    * `text_post/2` — a longer, image-free, day-by-day post.

  `opts`:

    * `:share_url` — the public plan URL (required for a useful caption).
    * `:locale` — language to render gettext'd chrome in (defaults to the plan's
      own `locale`, then `"en"`).
    * `:ingredient_names_by_id` / `:ingredient_names` / `:unit_names` — the same
      localized-name maps `MealPlanLive.Show` computes, used to resolve ingredient
      meal titles in the viewer's language. All optional (empty = English).
  """

  use Gettext, backend: MehungryWeb.Gettext

  alias MehungryWeb.CalendarLive.Calendar.Locale

  @base_hashtags ["mealprep", "mealplan", "mealplanning", "nutrition"]
  @text_hashtags ["mealprep", "mealplanning", "whatieatinaweek"]

  @doc """
  Short caption for the visual (image) post: title + truthful macro line + plan
  link + hashtags. Pairs with the downloaded PNG card.
  """
  def image_caption(plan, opts \\ []) do
    locale = locale(plan, opts)

    Gettext.with_locale(locale, fn ->
      [
        "🍽️ " <> plan.title,
        macro_line(plan),
        gettext("Full 7-day plan + grocery list 👉 %{url}", url: share_url(opts)),
        hashtags_line(@base_hashtags, plan)
      ]
      |> join_lines()
    end)
  end

  @doc """
  Longer, image-free text post: title, a day-by-day list of meal highlights, a
  macro + recipe-count line, and the plan link + hashtags. For X / Threads /
  Facebook status / WhatsApp, where plain text (not an image) is the unit.
  """
  def text_post(plan, opts \\ []) do
    locale = locale(plan, opts)

    Gettext.with_locale(locale, fn ->
      [
        "📋 " <> plan.title,
        "",
        day_lines(plan, locale, opts),
        "",
        stats_line(plan),
        gettext("🛒 Free grocery list included"),
        "",
        gettext("Build your own week 👉 %{url}", url: share_url(opts)),
        hashtags_line(@text_hashtags, plan)
      ]
      |> join_lines()
    end)
  end

  # ── Lines ─────────────────────────────────────────────────────────────────

  # Truthful macro one-liner — same rounded numbers as the page's macro tiles.
  defp macro_line(plan) do
    "~#{macro(plan, "energy_kcal")} kcal/day · #{macro(plan, "protein_g")}g protein · " <>
      "#{macro(plan, "carbs_g")}g carbs · #{macro(plan, "fat_g")}g fat"
  end

  defp stats_line(plan) do
    recipes =
      ngettext("%{count} recipe", "%{count} recipes", plan.recipe_count || 0,
        count: plan.recipe_count || 0
      )

    "📊 ~#{macro(plan, "energy_kcal")} kcal/day · #{macro(plan, "protein_g")}g protein avg · " <>
      recipes
  end

  # One line per non-empty day: "Monday: Dish · Dish · …".
  defp day_lines(plan, locale, opts) do
    plan.days
    |> Enum.map(fn day -> {day_label(day, locale), meal_titles(day, opts)} end)
    |> Enum.reject(fn {_label, titles} -> titles == [] end)
    |> Enum.map(fn {label, titles} -> "#{label}: #{Enum.join(titles, " · ")}" end)
    |> join_lines()
  end

  # Flattened, de-duplicated item titles across all of a day's meals, localized
  # through the same maps the page uses (recipe titles come straight from the
  # snapshot; ingredient/free-food names resolve by id then name).
  defp meal_titles(day, opts) do
    for meal <- day["meals"] || [],
        item <- meal["items"] || [],
        title = item_title(item, opts),
        is_binary(title) and title != "",
        uniq: true,
        do: title
  end

  defp item_title(%{"kind" => "recipe", "title" => title}, _opts), do: title

  defp item_title(item, opts) do
    by_id = opts[:ingredient_names_by_id] || %{}
    by_name = opts[:ingredient_names] || %{}

    case item["ingredient_id"] do
      id when not is_nil(id) and is_map_key(by_id, id) -> by_id[id]
      _ -> Map.get(by_name, item["title"], item["title"])
    end
  end

  # ── Hashtags ────────────────────────────────────────────────────────────────

  defp hashtags_line(base, plan) do
    (base ++ List.wrap(goal_hashtag(plan)))
    |> Enum.map_join(" ", &("#" <> &1))
  end

  # A hashtag derived from the goal label ("Anti-inflammatory" → "antiinflammatory"),
  # only when the plan carries one.
  defp goal_hashtag(%{goal_label: label}) when is_binary(label) and label != "" do
    tag = label |> String.downcase() |> String.replace(~r/[^a-z0-9]/u, "")
    if tag == "", do: nil, else: tag
  end

  defp goal_hashtag(_plan), do: nil

  # ── Helpers ──────────────────────────────────────────────────────────────────

  # Localized weekday label from the day's stored ISO date, mirroring the page's
  # `day_weekday_label/2` (falls back to the stored English label, then day index).
  defp day_label(%{"date" => iso} = day, locale) when is_binary(iso) do
    case Date.from_iso8601(iso) do
      {:ok, d} -> Locale.day_name(d, locale)
      _ -> day["label"] || gettext("Day %{n}", n: (day["index"] || 0) + 1)
    end
  end

  defp day_label(day, _locale),
    do: day["label"] || gettext("Day %{n}", n: (day["index"] || 0) + 1)

  # Same rounding as `MealPlanLive.Show.macro/2`: whole floats shown as ints.
  defp macro(plan, key) do
    case plan.macros[key] do
      n when is_float(n) -> n |> Float.round(1) |> trim_float()
      n when is_integer(n) -> n
      _ -> 0
    end
  end

  defp trim_float(f), do: if(f == Float.round(f), do: round(f), else: f)

  defp locale(plan, opts), do: opts[:locale] || Map.get(plan, :locale) || "en"

  defp share_url(opts), do: opts[:share_url] || ""

  defp join_lines(lines), do: lines |> List.flatten() |> Enum.join("\n")
end
