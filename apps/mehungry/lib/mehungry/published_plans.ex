defmodule Mehungry.PublishedPlans do
  @moduledoc """
  Published, public, crawlable weekly meal plans — the SEO + sharing surface for
  meal planning.

  A user's live calendar is private and `noindex`, so it can never rank. This
  context turns a *chosen week* of that calendar into an immutable public
  snapshot (`PublishedMealPlan`) served at `/meal-plans/:slug`: a synchronously
  rendered page carrying day-by-day meals (each recipe linking to `/browse/:id`),
  the truthful daily-average macros, an aggregated grocery list, and a short
  prose summary — exactly the "7-day meal plan" content people search for, with
  nutrition no recipe-blog listicle can match.

  `publish_week/3` is **self-contained**: it re-derives the week from the DB via
  `History.list_calendar_user_meals/3` + `History.format_user_meals/1`, so the
  caller only passes `(user, week_start)` — no LiveView socket state. Macro
  numbers come from `Mehungry.NutrientUtils` (the same functions the calendar
  uses), so the snapshot matches the calendar to the gram.
  """

  import Ecto.Query, warn: false

  alias Mehungry.Repo
  alias Mehungry.{History, NutrientUtils}
  alias Mehungry.History.MealType
  alias Mehungry.Food.{Ingredient, RecipeIngredient}
  alias Mehungry.PublishedPlans.{GroceryAisle, PublishedMealPlan}

  @doc """
  Publishes the given week of `user`'s calendar as a public, crawlable plan.

  `opts`: `:title`, `:goal_label`, `:locale`, `:og_image_url` (e.g. the share
  card produced by the weekly-plan-graphic feature). Returns
  `{:error, :empty_week}` when the week has no meals.
  """
  @spec publish_week(struct(), Date.t(), keyword()) ::
          {:ok, PublishedMealPlan.t()} | {:error, term()}
  def publish_week(user, %Date{} = week_start, opts \\ []) do
    week_end = Date.add(week_start, 6)

    # Raw meals carry the FK ids (recipe/ingredient/unit) the snapshot needs so a
    # viewer can one-click re-create the week on their own calendar; the formatted
    # view is only for the macro summary (it reads the stored nutrient maps).
    raw =
      user.id
      |> History.list_calendar_user_meals(week_start, week_end)
      |> Enum.filter(&raw_in_week?(&1, week_start, week_end))

    if raw == [] do
      {:error, :empty_week}
    else
      goal_label = opts[:goal_label]
      locale = opts[:locale] || "en"
      title = opts[:title] || default_title(goal_label, week_start)

      days = build_days(raw, week_start)
      macros = build_macros(History.format_user_meals(raw))
      grocery_groups = build_grocery_groups(raw)
      grocery = flatten_grocery_names(grocery_groups)
      recipe_count = count_recipes(raw)
      summary = build_summary(macros, recipe_count, title)

      attrs = %{
        user_id: user.id,
        title: title,
        goal_label: goal_label,
        locale: locale,
        week_start: week_start,
        days: days,
        macros: macros,
        grocery: grocery,
        grocery_groups: grocery_groups,
        summary_text: summary,
        og_image_url: opts[:og_image_url],
        recipe_count: recipe_count,
        visibility: "public",
        published_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }

      upsert_week_plan(user.id, week_start, attrs, title)
    end
  end

  # One published plan per `(user, week_start)`: re-publishing the same week
  # **replaces** the old plan in place (keeping its `slug`, so the public
  # `/meal-plans/:slug` URL and any shared links stay stable) rather than leaving
  # two plans for the same dates. Any stray duplicates from before this invariant
  # are cleaned up.
  defp upsert_week_plan(user_id, week_start, attrs, title) do
    existing =
      Repo.all(
        from(p in PublishedMealPlan,
          where: p.user_id == ^user_id and p.week_start == ^week_start,
          order_by: [asc: p.id]
        )
      )

    case existing do
      [] ->
        %PublishedMealPlan{}
        |> PublishedMealPlan.changeset(Map.put(attrs, :slug, unique_slug(title)))
        |> Repo.insert()

      [keep | extras] ->
        Enum.each(extras, &Repo.delete/1)

        keep
        |> PublishedMealPlan.changeset(attrs)
        |> Repo.update()
    end
  end

  @doc "A public plan by slug (author preloaded), or `nil`."
  def get_public_plan_by_slug(slug) when is_binary(slug) do
    PublishedMealPlan
    |> Repo.get_by(slug: slug, visibility: "public")
    |> Repo.preload(:user)
  end

  @doc "A public plan by slug (author preloaded), raising if absent/private."
  def get_public_plan_by_slug!(slug) when is_binary(slug) do
    PublishedMealPlan
    |> Repo.get_by!(slug: slug, visibility: "public")
    |> Repo.preload(:user)
  end

  @doc "All public plans, newest first (for the sitemap)."
  def list_public_plans(opts \\ []) do
    query =
      from(p in PublishedMealPlan,
        where: p.visibility == "public",
        order_by: [desc: p.published_at],
        select: %{slug: p.slug, updated_at: p.updated_at}
      )

    query = if l = opts[:limit], do: limit(query, ^l), else: query
    Repo.all(query)
  end

  @doc """
  Full public-plan rows (author + professional profile preloaded), newest first —
  the discovery surface for the browse "Meal Plans" tab and the crawlable
  `/meal-plans` index page. Options: `:limit`, `:offset`.
  """
  def list_public_plans_detailed(opts \\ []) do
    PublishedMealPlan
    |> where([p], p.visibility == "public")
    |> order_by([p], desc: p.published_at)
    |> maybe_paginate(opts)
    |> Repo.all()
    |> Repo.preload(user: :professional_profile)
  end

  @doc """
  Public plans whose `title` matches `term` (case-insensitive substring), newest
  first, author + professional profile preloaded. A blank term returns all public
  plans. Mirrors `Mehungry.MealBlueprints.search_public_blueprints/2`. Options:
  `:limit`, `:offset`.
  """
  def search_public_plans(term, opts \\ [])

  def search_public_plans(term, opts) when is_binary(term) do
    trimmed = String.trim(term)

    if trimmed == "" do
      list_public_plans_detailed(opts)
    else
      pattern = "%#{trimmed}%"

      PublishedMealPlan
      |> where([p], p.visibility == "public" and ilike(p.title, ^pattern))
      |> order_by([p], desc: p.published_at)
      |> maybe_paginate(opts)
      |> Repo.all()
      |> Repo.preload(user: :professional_profile)
    end
  end

  def search_public_plans(_term, opts), do: list_public_plans_detailed(opts)

  defp maybe_paginate(query, opts) do
    query
    |> then(fn q -> if l = opts[:limit], do: limit(q, ^l), else: q end)
    |> then(fn q -> if o = opts[:offset], do: offset(q, ^o), else: q end)
  end

  @doc "How many published plans a user owns — cheap COUNT for tab badges."
  def count_plans_for_user(user_id) do
    Repo.aggregate(from(p in PublishedMealPlan, where: p.user_id == ^user_id), :count, :id)
  end

  @doc "A user's published plans, newest first."
  def list_plans_for_user(user_id) do
    Repo.all(
      from(p in PublishedMealPlan,
        where: p.user_id == ^user_id,
        order_by: [desc: p.published_at]
      )
    )
  end

  @doc """
  A single plan owned by `user_id`, raising if it is absent or belongs to another
  user — the owner-scoped getter to use before mutating (e.g. unpublish) so a
  forged id can't touch someone else's plan.
  """
  def get_user_plan!(user_id, id),
    do: Repo.get_by!(PublishedMealPlan, id: id, user_id: user_id)

  @doc "Deletes a published plan (unpublish)."
  def delete_plan(%PublishedMealPlan{} = plan), do: Repo.delete(plan)

  @doc """
  Upgrades `grocery_groups` on older plans so they match the current shape,
  re-deriving everything from the stored item names (resolved to ingredient
  categories **and ids**) and applying the same water filter. Covers two legacy
  states so old shared links localize the grocery list by id without being
  re-published:

    * plans published before aisle grouping existed (flat `grocery` populated,
      `grocery_groups` empty), and
    * plans whose `grocery_groups` items are still plain name strings (before the
      grocery list carried `ingredient_id`).

  Returns the number of plans updated.
  """
  @spec backfill_grocery_groups() :: non_neg_integer()
  def backfill_grocery_groups do
    PublishedMealPlan
    |> Repo.all()
    |> Enum.reduce(0, fn plan, n ->
      case upgrade_grocery_groups(plan) do
        nil ->
          n

        groups ->
          {:ok, _} =
            plan
            |> PublishedMealPlan.changeset(%{
              grocery_groups: groups,
              grocery: flatten_grocery_names(groups)
            })
            |> Repo.update()

          n + 1
      end
    end)
  end

  # Returns upgraded `grocery_groups` (map items with ids) for a legacy plan, or
  # nil when the plan is already current. Both legacy states are re-derived from
  # the stored names via `group_names_by_aisle/1`, which attaches ids by matching
  # the catalog-normalized `search_name`.
  defp upgrade_grocery_groups(%{grocery_groups: [_ | _] = groups}) do
    if Enum.any?(groups, fn g -> Enum.any?(g["items"] || [], &is_binary/1) end) do
      groups
      |> Enum.flat_map(fn g -> Enum.map(g["items"] || [], &grocery_item_name/1) end)
      |> group_names_by_aisle()
    end
  end

  defp upgrade_grocery_groups(%{grocery_groups: groups, grocery: [_ | _] = flat})
       when groups in [nil, []],
       do: group_names_by_aisle(flat)

  defp upgrade_grocery_groups(_plan), do: nil

  # Name of a grocery item, tolerating both the current map shape and the legacy
  # plain-string shape.
  defp grocery_item_name(%{"name" => name}), do: name
  defp grocery_item_name(name) when is_binary(name), do: name

  # The flat `grocery` list (names only) kept in sync with the grouped list — a
  # backward-compatible fallback for consumers that only want names.
  defp flatten_grocery_names(groups) do
    Enum.flat_map(groups, fn g -> Enum.map(g["items"], &grocery_item_name/1) end)
  end

  @doc """
  Re-creates a published plan's week on `user_id`'s calendar, laying day-index
  0..6 onto `start_date`..`+6`. **Non-destructive** — it adds `History.UserMeal`
  rows without clearing the user's existing meals. Recipe and whole-food
  ingredient slots are recreated from the snapshot's FK ids; free-food / items
  missing their ids (e.g. plans published before the snapshot stored FKs) are
  skipped. Returns `{:ok, created, skipped}`.
  """
  @spec import_to_calendar(PublishedMealPlan.t(), integer(), Date.t()) ::
          {:ok, non_neg_integer(), non_neg_integer()}
  def import_to_calendar(%PublishedMealPlan{} = plan, user_id, %Date{} = start_date) do
    results =
      for day <- plan.days, meal <- day["meals"] || [] do
        import_day_meal(day, meal, user_id, start_date)
      end

    created = Enum.count(results, &match?({:ok, _}, &1))
    skipped = Enum.count(results, &(not match?({:ok, _}, &1)))
    {:ok, created, skipped}
  end

  defp import_day_meal(day, meal, user_id, start_date) do
    date = Date.add(start_date, day["index"] || 0)
    meal_type = meal["meal_type"]
    items = meal["items"] || []

    recipe_attrs = import_recipe_attrs(items)
    ingredient_attrs = import_ingredient_attrs(items)

    if recipe_attrs == [] and ingredient_attrs == [] do
      {:error, :nothing_importable}
    else
      History.create_user_meal(%{
        title: MealType.label(meal_type),
        meal_type: meal_type,
        start_dt: NaiveDateTime.new!(date, MealType.slot_time(meal_type)),
        user_id: user_id,
        recipe_user_meals: recipe_attrs,
        ingredient_user_meals: ingredient_attrs
      })
    end
  end

  defp import_recipe_attrs(items) do
    for %{"kind" => "recipe", "recipe_id" => rid} = it <- items, not is_nil(rid) do
      %{
        recipe_id: rid,
        cooking_portions: it["cooking_portions"] || 2,
        consume_portions: it["consume_portions"] || 1,
        cooking: true
      }
    end
  end

  defp import_ingredient_attrs(items) do
    for %{"kind" => "ingredient", "ingredient_id" => iid} = it <- items, not is_nil(iid) do
      %{
        ingredient_id: iid,
        quantity: it["quantity"] || 1.0,
        measurement_unit_id: it["measurement_unit_id"],
        ingredient_portion_id: it["ingredient_portion_id"]
      }
    end
  end

  # ── Snapshot builders ───────────────────────────────────────────────────────

  defp raw_in_week?(%{start_dt: %NaiveDateTime{} = dt}, week_start, week_end) do
    d = NaiveDateTime.to_date(dt)
    Date.compare(d, week_start) != :lt and Date.compare(d, week_end) != :gt
  end

  defp raw_in_week?(_meal, _week_start, _week_end), do: false

  # One entry per calendar day (Mon..Sun offset 0..6), each with its meals
  # ordered by canonical meal type, each meal's items ordered recipe → ingredient
  # → free-food. Built from the *raw* `UserMeal` rows so each item carries the FK
  # ids needed to re-create it (recipe_id / ingredient_id / unit). String keys
  # (jsonb-friendly).
  defp build_days(raw_meals, week_start) do
    by_date = Enum.group_by(raw_meals, fn m -> NaiveDateTime.to_date(m.start_dt) end)

    for offset <- 0..6 do
      date = Date.add(week_start, offset)
      day_meals = Map.get(by_date, date, [])

      %{
        "index" => offset,
        "date" => Date.to_iso8601(date),
        "label" => Calendar.strftime(date, "%A"),
        "meals" => build_day_meals(day_meals)
      }
    end
  end

  defp build_day_meals(day_meals) do
    by_type = Enum.group_by(day_meals, fn m -> Map.get(m, :meal_type) end)

    for meal_type <- MealType.ordered() ++ [nil],
        meals = Map.get(by_type, meal_type, []),
        meals != [],
        reduce: [] do
      acc ->
        items = Enum.flat_map(meals, &meal_items/1)

        if items == [],
          do: acc,
          else: acc ++ [%{"meal_type" => to_string_or_nil(meal_type), "items" => items}]
    end
  end

  defp meal_items(meal) do
    recipes =
      meal
      |> Map.get(:recipe_user_meals, [])
      |> Enum.map(fn r ->
        %{
          "kind" => "recipe",
          "title" => r.recipe && r.recipe.title,
          "recipe_id" => r.recipe_id,
          "servings" => r.recipe && r.recipe.servings,
          "image_url" => r.recipe && r.recipe.image_url,
          "cooking_portions" => r.cooking_portions,
          "consume_portions" => r.consume_portions
        }
      end)

    ingredients =
      meal
      |> Map.get(:ingredient_user_meals, [])
      |> Enum.map(fn i ->
        %{
          "kind" => "ingredient",
          "title" => i.ingredient && i.ingredient.name,
          "ingredient_id" => i.ingredient_id,
          "quantity" => i.quantity,
          "unit" => RecipeIngredient.unit_label(i),
          "measurement_unit_id" => i.measurement_unit_id,
          "ingredient_portion_id" => i.ingredient_portion_id
        }
      end)

    free =
      meal
      |> Map.get(:free_food_user_meals, [])
      |> Enum.map(fn f -> %{"kind" => "free_food", "title" => f.name} end)

    (recipes ++ ingredients ++ free)
    |> Enum.reject(&(is_nil(&1["title"]) or &1["title"] == ""))
  end

  # Daily-average macro summary: week total ÷ 7, through the same shared
  # functions the calendar's week header uses.
  defp build_macros(meals) do
    summary =
      meals
      |> NutrientUtils.summarize_meals_nutrients()
      |> NutrientUtils.scale_nutrient_map(1 / 7)
      |> NutrientUtils.macro_summary()

    %{
      "energy_kcal" => summary.energy_kcal,
      "protein_g" => summary.protein_g,
      "carbs_g" => summary.carbs_g,
      "fat_g" => summary.fat_g,
      "sugars_g" => summary.sugars_g,
      "fiber_g" => summary.fiber_g
    }
  end

  defp count_recipes(meals) do
    meals
    |> Enum.flat_map(fn m -> Enum.map(Map.get(m, :recipe_user_meals, []), & &1.recipe_id) end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> length()
  end

  # Aggregated weekly shopping list, grouped into friendly shopping **aisles**
  # (`GroceryAisle`). Entries come from every recipe in the plan (ingredients +
  # their food category, loaded in one query) plus every directly-logged
  # ingredient and free food. We list names (not summed quantities) — summing
  # across mismatched units would be misleading.
  #
  # De-dup is on the ingredient's stored, catalog-normalized `search_name` (the
  # reliable key), so "Olive oil " and "olive oil" collapse and the same
  # ingredient reached through several recipes appears once. Returns an ordered
  # list of `%{"aisle" => key, "label" => label, "items" => [names]}`, empty
  # aisles dropped, names alphabetical within each aisle.
  defp build_grocery_groups(meals) do
    (recipe_ingredient_entries(meals) ++ logged_entries(meals))
    |> Enum.reject(&(is_nil(&1.name) or String.trim(&1.name) == ""))
    |> Enum.map(fn e -> %{e | name: String.trim(e.name)} end)
    |> Enum.reject(&plain_water?(&1.name))
    |> Enum.uniq_by(&dedup_key/1)
    |> Enum.group_by(& &1.aisle)
    |> group_in_aisle_order()
  end

  # Plain drinking water is assumed on hand and never bought by the item, so it's
  # dropped from the shopping list. We only strip *plain* water (USDA
  # "Water, tap/bottled/…" whose first comma-segment is just "water", or common
  # phrasings like "tap water") — never water-bearing foods like watermelon,
  # water chestnut, coconut water or rose water.
  @plain_water_phrases ~w(water)
  @plain_water_descriptors ~w(tap bottled drinking sparkling mineral still spring carbonated soda municipal distilled)
  defp plain_water?(name) when is_binary(name) do
    normalized = Ingredient.normalize_string(name)
    first_segment = name |> String.split(",") |> List.first() |> to_string() |> String.trim()

    cond do
      normalized in @plain_water_phrases -> true
      String.downcase(first_segment) == "water" -> true
      # "<descriptor> water" display phrasings, e.g. "sparkling water".
      match?([d, "water"] when d in @plain_water_descriptors, String.split(normalized)) -> true
      true -> false
    end
  end

  defp plain_water?(_), do: false

  defp recipe_ingredient_entries(meals) do
    recipe_ids =
      meals
      |> Enum.flat_map(fn m -> Enum.map(Map.get(m, :recipe_user_meals, []), & &1.recipe_id) end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    if recipe_ids == [] do
      []
    else
      Repo.all(
        from(ri in RecipeIngredient,
          join: ing in assoc(ri, :ingredient),
          left_join: cat in assoc(ing, :category),
          where: ri.recipe_id in ^recipe_ids,
          select: %{id: ing.id, name: ing.name, search_name: ing.search_name, category: cat.name}
        )
      )
      |> Enum.map(&to_entry/1)
    end
  end

  # Directly-logged ingredients (looked up fresh with their category so we don't
  # depend on the raw meals having `:category` preloaded) plus free foods, which
  # have no category and land in "other".
  defp logged_entries(meals) do
    ingredient_ids =
      meals
      |> Enum.flat_map(fn m ->
        Enum.map(Map.get(m, :ingredient_user_meals, []), & &1.ingredient_id)
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    logged_ingredients =
      if ingredient_ids == [] do
        []
      else
        Repo.all(
          from(ing in Ingredient,
            left_join: cat in assoc(ing, :category),
            where: ing.id in ^ingredient_ids,
            select: %{id: ing.id, name: ing.name, search_name: ing.search_name, category: cat.name}
          )
        )
        |> Enum.map(&to_entry/1)
      end

    # Free foods are plain text (no catalog ingredient), so they carry no id and
    # fall into the "other" aisle.
    free_foods =
      meals
      |> Enum.flat_map(fn m -> Map.get(m, :free_food_user_meals, []) end)
      |> Enum.map(fn f -> to_entry(%{id: nil, name: f.name, search_name: nil, category: nil}) end)

    logged_ingredients ++ free_foods
  end

  defp to_entry(%{name: name, search_name: search_name, category: category} = e) do
    %{
      id: Map.get(e, :id),
      name: name,
      search_name: search_name,
      aisle: GroceryAisle.classify(category)
    }
  end

  # Groups a flat list of item names into aisles by resolving each name back to
  # its ingredient's category (matched on the catalog-normalized `search_name`).
  # Used by `backfill_grocery_groups/0` for pre-grouping plans. Names with no
  # matching ingredient fall into "other".
  defp group_names_by_aisle(names) do
    names =
      names
      |> Enum.reject(&(is_nil(&1) or String.trim(&1) == ""))
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&plain_water?/1)

    search_names = names |> Enum.map(&Ingredient.normalize_string/1) |> Enum.uniq()

    by_search =
      if search_names == [] do
        %{}
      else
        Repo.all(
          from(ing in Ingredient,
            left_join: cat in assoc(ing, :category),
            where: ing.search_name in ^search_names,
            select: {ing.search_name, {ing.id, cat.name}}
          )
        )
        |> Map.new()
      end

    names
    |> Enum.uniq_by(&Ingredient.normalize_string/1)
    |> Enum.map(fn name ->
      {id, category} = Map.get(by_search, Ingredient.normalize_string(name), {nil, nil})
      %{id: id, name: name, aisle: GroceryAisle.classify(category)}
    end)
    |> Enum.group_by(& &1.aisle)
    |> group_in_aisle_order()
  end

  # Dedup on the catalog ingredient id when known (the reliable key — the same
  # ingredient reached through several recipes / logged slots collapses to one),
  # else the normalized name for free foods and unresolved legacy names.
  defp dedup_key(%{id: id}) when is_integer(id), do: {:id, id}

  defp dedup_key(%{search_name: sn, name: name}) do
    case sn do
      s when is_binary(s) and s != "" -> {:name, s}
      _ -> {:name, Ingredient.normalize_string(name)}
    end
  end

  # Each item carries its `ingredient_id` (nil for free foods / unresolved) so
  # the public page can localize the grocery list by id — bullet-proof against
  # name drift — exactly as the per-day ingredient meals already are.
  defp group_in_aisle_order(by_aisle) do
    for {aisle, label} <- GroceryAisle.ordered(),
        entries = Map.get(by_aisle, aisle, []),
        entries != [] do
      items =
        entries
        |> Enum.sort_by(&String.downcase(&1.name))
        |> Enum.map(fn e -> %{"ingredient_id" => Map.get(e, :id), "name" => e.name} end)

      %{"aisle" => aisle, "label" => label, "items" => items}
    end
  end

  defp build_summary(macros, recipe_count, title) do
    kcal = macros["energy_kcal"] || 0
    protein = round(macros["protein_g"] || 0)
    carbs = round(macros["carbs_g"] || 0)
    fat = round(macros["fat_g"] || 0)

    recipe_clause =
      cond do
        recipe_count == 0 -> ""
        recipe_count == 1 -> " built around 1 recipe"
        true -> " built around #{recipe_count} recipes"
      end

    "#{title} — a full 7-day meal plan#{recipe_clause}, averaging about " <>
      "#{kcal} kcal per day with #{protein} g protein, #{carbs} g carbohydrate and " <>
      "#{fat} g fat, each with full USDA nutrition and a weekly grocery list."
  end

  defp default_title(goal_label, week_start) do
    range =
      "#{short_date(week_start)} – #{short_date(Date.add(week_start, 6))}"

    if goal_label in [nil, ""],
      do: "7-Day Meal Plan · #{range}",
      else: "#{goal_label} · 7-Day Meal Plan"
  end

  defp short_date(date) do
    date |> Calendar.strftime("%d %b") |> String.replace_leading("0", "")
  end

  defp to_string_or_nil(nil), do: nil
  defp to_string_or_nil(v), do: to_string(v)

  # ── Slug ────────────────────────────────────────────────────────────────────

  defp unique_slug(title) do
    "#{slugify(title)}-#{random_suffix()}"
  end

  @doc false
  def slugify(nil), do: "meal-plan"

  def slugify(string) do
    slug =
      string
      |> String.downcase()
      |> :unicode.characters_to_nfd_binary()
      |> String.replace(~r/[^a-z0-9\s-]/u, "")
      |> String.trim()
      |> String.replace(~r/[\s-]+/, "-")

    if slug == "", do: "meal-plan", else: slug
  end

  defp random_suffix do
    :crypto.strong_rand_bytes(4) |> Base.url_encode64(padding: false) |> String.downcase()
  end
end
