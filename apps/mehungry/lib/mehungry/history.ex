defmodule Mehungry.History do
  @moduledoc """
  The History context.
  """

  import Ecto.Query, warn: false
  require Logger
  alias Mehungry.History.ConsumeRecipeUserMeal
  alias Mehungry.History
  alias Mehungry.History.IngredientUserMeal
  alias Mehungry.Food.NutrientCalculation
  alias Mehungry.Food.Localization
  alias Mehungry.Repo

  alias Mehungry.History.UserMeal

  @doc """
  Returns the list of history_user_meals.

  ## Examples

      iex> list_history_user_meals()
      [%UserMeal{}, ...]

  """
  def list_history_user_meals do
    Repo.all(UserMeal)
    |> Repo.preload(
      recipe_user_meals: [
        recipe: [
          recipe_ingredients: [
            :measurement_unit,
            :ingredient_portion,
            ingredient: [:category, :ingredient_translation, :ingredient_nutrients]
          ]
        ]
      ]
    )
  end

  alias History.RecipeUserMeal

  def get_available_portions_for_user_meal(recipe_user_meal_id) do
    result =
      from(cum in ConsumeRecipeUserMeal,
        join: rum in RecipeUserMeal,
        on: rum.id == ^recipe_user_meal_id,
        where: cum.user_meal_id == rum.user_meal_id
      )
      |> Repo.aggregate(:sum, :consume_portions)

    recipe_user_meal =
      from(rum in RecipeUserMeal, where: rum.id == ^recipe_user_meal_id)
      |> Repo.one()

    result =
      case result do
        nil ->
          0

        anything_else ->
          anything_else
      end

    recipe_user_meal.cooking_portions - (result + recipe_user_meal.consume_portions)
  end

  # TODO use the date_time to only show incomplete meals to show user warning
  def list_incomplete_user_meals2(user_id, _date_time) do
    query =
      from rum in RecipeUserMeal,
        join: um in UserMeal,
        on: um.id == rum.user_meal_id,
        left_join: cum in ConsumeRecipeUserMeal,
        on: cum.user_meal_id == um.id,
        where: um.user_id == ^user_id and rum.cooking_portions > rum.consume_portions,
        having:
          (is_nil(cum.consume_portions) and rum.consume_portions < rum.cooking_portions) or
            sum(cum.consume_portions) + rum.consume_portions < rum.cooking_portions,
        group_by: [cum.id, rum.id, um.id]

    Repo.all(query)
    |> Repo.preload([:user_meal, :recipe])
  end

  def list_history_user_meals_for_user(user_id) do
    query =
      from meal in UserMeal,
        where: meal.user_id == ^user_id

    Repo.all(query)
    |> preload_calendar_meals()
  end

  @doc """
  The calendar's loader: a user's `UserMeal`s whose `start_dt` falls in the
  inclusive `start_date..end_date` span (one visible week), preloaded only as
  deeply as `format_user_meals/1` needs to render the grid. Recipe cards read the
  stored `recipe.nutrients` jsonb (so `recipe_ingredients` is not loaded), and
  ingredient cards read the stored `ingredient_user_meals.nutrients` jsonb (so the
  deep `ingredient_nutrients`/`ingredient_portions` tree is not loaded).

  Replaces the unbounded `list_history_user_meals_for_user/1` on the calendar
  surfaces — the calendar only ever shows one week, so loading the user's entire
  history on every mount/mutation was the dominant source of slowness.

  Distinct from `list_user_meals_in_range/3`, which keeps the heavy preloads its
  blueprint-compatibility consumer needs.
  """
  def list_calendar_user_meals(user_id, %Date{} = start_date, %Date{} = end_date) do
    range_start = NaiveDateTime.new!(start_date, ~T[00:00:00])
    range_end = NaiveDateTime.new!(end_date, ~T[23:59:59])

    query =
      from meal in UserMeal,
        where:
          meal.user_id == ^user_id and meal.start_dt >= ^range_start and
            meal.start_dt <= ^range_end

    Repo.all(query)
    |> preload_calendar_meals()
  end

  # The light preload set the calendar surfaces need: recipe cards read the stored
  # `recipe.nutrients` jsonb (no `recipe_ingredients`), ingredient cards read the
  # stored `ingredient_user_meals.nutrients` jsonb (no deep `ingredient_nutrients`
  # tree) plus the name/unit for display. Shared by `list_calendar_user_meals/3`
  # and the single-arg / single-day `list_history_user_meals_for_user` loaders.
  defp preload_calendar_meals(meals) do
    Repo.preload(meals,
      recipe_user_meals: [:recipe],
      ingredient_user_meals: [:measurement_unit, :ingredient_portion, :ingredient],
      free_food_user_meals: []
    )
  end

  @doc """
  The hierarchical nutrient map for a logged ingredient meal, in the **same**
  structured shape as a recipe's `recipe.nutrients` (via
  `NutrientCalculation.ingredient_nutrient_tree/2`). Treating a directly-logged
  ingredient as a one-ingredient recipe keeps the calendar's daily summary
  (`NutrientUtils.summarize_meals_nutrients/1`) and cards consistent between the
  two meal kinds.

  Resolves the ingredient's total grams from the chosen portion/unit + quantity
  (reusing the recipe nutrition engine) so a logged "2 medium banana" contributes
  twice a banana's nutrients rather than a flat per-100g figure. Pass `gram_ids`
  (from `NutrientCalculation.gram_unit_ids/0`) so the caller resolves the
  gram-unit set once for a whole calendar instead of per row.

  `ingredient_user_meal` must have `:ingredient` preloaded with
  `:ingredient_portions` and `ingredient_nutrients: [nutrient: :measurement_unit]`.
  """
  def scaled_ingredient_nutrient_tree(ingredient_user_meal, gram_ids) do
    ingredient = ingredient_user_meal.ingredient

    gram_weight =
      NutrientCalculation.calculate_gram_weight(
        ingredient,
        ingredient_user_meal.measurement_unit_id,
        ingredient_user_meal.ingredient_portion_id,
        ingredient_user_meal.quantity,
        gram_ids
      )

    NutrientCalculation.ingredient_nutrient_tree(ingredient, gram_weight)
  end

  @doc """
  The nutrient map for an arbitrary "free food" entry, in the **same** shape as a
  recipe's/ingredient's tree so the daily summary merges all three kinds
  uniformly. The food's client-supplied per-100g nutrients are scaled by its
  resolved `grams` (`NutrientUtils.per_100g_to_tree/2`, factor = grams / 100).
  """
  def scaled_free_food_nutrient_tree(free_food_user_meal) do
    Mehungry.NutrientUtils.per_100g_to_tree(
      free_food_user_meal.nutrients_per_100g,
      free_food_user_meal.grams
    )
  end

  @doc """
  The **single, shared** calendar view-model: shapes raw `UserMeal`s (preloaded
  via `list_history_user_meals_for_user/1,2,3`) into the display + nutrient form
  the calendar consumes. Recipe meals carry the recipe's stored `nutrients` map
  (scaled to the consumed fraction inside `NutrientUtils.summarize_meals_nutrients/1`);
  directly-logged ingredient meals carry the scaled nutrient tree as `recipe.nutrients`
  so the summariser merges both kinds uniformly.

  Reused verbatim by the consumer calendar (`CalendarLive.Index`), the
  nutritionist client calendar (`NutritionistLive.ClientCalendar`) and the mobile
  REST daily-nutrition endpoint (`Api.V1.MealController.nutrition`) — keep it the
  one source of truth rather than re-deriving the shape per surface.
  """
  def format_user_meals(meals, locale \\ nil) when is_list(meals) do
    ctx = translation_context(meals, locale)
    Enum.map(meals, &format_user_meal(&1, ctx))
  end

  # Batched translation lookups for the whole meal set — ingredient display
  # names, measurement-unit labels, and recipe titles — so localizing the
  # view-model costs three queries, not N+1. A no-op (empty maps) for the source
  # locale, keeping the English path exactly as before.
  defp translation_context(_meals, locale) when locale in [nil, "en", "En"],
    do: %{ingredients: %{}, units: %{}, recipes: %{}}

  defp translation_context(meals, locale) do
    # A locale maps to several translation codes (canonical ISO + legacy alias,
    # e.g. "el" + "Gr"); ingredient/unit rows are stored under the ISO code today
    # but legacy "Gr" rows may still exist, so read both (ISO wins on conflict) —
    # the same resolution `load_recipe_translations_map/2` does for recipes.
    codes = Mehungry.Languages.Locale.data_codes(locale)

    ingredient_ids = Enum.uniq(for m <- meals, ium <- m.ingredient_user_meals, do: ium.ingredient_id)

    unit_ids =
      Enum.uniq(
        for m <- meals,
            ium <- m.ingredient_user_meals,
            not is_nil(ium.measurement_unit_id),
            do: ium.measurement_unit_id
      )

    recipe_ids = Enum.uniq(for m <- meals, rum <- m.recipe_user_meals, do: rum.recipe_id)

    %{
      ingredients:
        merge_by_codes(codes, &Localization.ingredient_display_names(ingredient_ids, &1)),
      units: merge_by_codes(codes, &Localization.get_unit_translations_map(unit_ids, &1)),
      recipes: Localization.load_recipe_translations_map(recipe_ids, locale)
    }
  end

  # Merges a per-code translation map across a locale's codes, with the canonical
  # (first/ISO) code winning on conflict.
  defp merge_by_codes(codes, fun) do
    codes
    |> Enum.reverse()
    |> Enum.reduce(%{}, fn code, acc -> Map.merge(acc, fun.(code)) end)
  end

  defp format_user_meal(meal, ctx) do
    %{
      id: meal.id,
      start_dt: meal.start_dt,
      end: meal.end_dt,
      title: meal.title,
      meal_type: meal.meal_type,
      ingredient_user_meals:
        Enum.map(meal.ingredient_user_meals, fn y ->
          %{
            title: Map.get(ctx.ingredients, y.ingredient_id) || y.ingredient.name,
            portions: y.quantity,
            measurement_unit: localized_unit_label(y, ctx.units),
            primary_size: 6,
            img_url: nil,
            recipe: %{
              id: y.ingredient.id,
              # Read the denormalized tree stored at write time (see
              # `put_ingredient_user_meal_nutrients/1`). Empty until the row is
              # written/backfilled — never recompute here (the deep nutrient
              # preload is no longer loaded on the calendar surface).
              nutrients: y.nutrients || %{},
              primary_size: 5
            }
          }
        end),
      recipe_user_meals:
        Enum.map(meal.recipe_user_meals, fn y ->
          %{
            title: localized_recipe_title(y.recipe, Map.get(ctx.recipes, y.recipe.id)),
            consume_portions: y.consume_portions,
            cooking_portions: y.cooking_portions,
            servings: y.recipe.servings,
            recipe_nutrients: y.recipe.nutrients,
            img_url: y.recipe.image_url,
            primary_size: y.recipe.primary_nutrients_size,
            recipe_id: y.recipe.id
          }
        end),
      free_food_user_meals:
        Enum.map(free_food_user_meals(meal), fn y ->
          %{
            id: y.id,
            title: y.name,
            grams: y.grams,
            portion_name: y.portion_name,
            portion_grams: y.portion_grams,
            portions: y.portions,
            primary_size: 6,
            img_url: nil,
            recipe: %{
              id: y.id,
              nutrients: scaled_free_food_nutrient_tree(y),
              primary_size: 5
            }
          }
        end)
    }
  end

  # The localized measurement-unit label for a logged ingredient, falling back to
  # the English `RecipeIngredient.unit_label/1` (which also handles description-only
  # portions) when no translation exists for the unit.
  defp localized_unit_label(ingredient_user_meal, unit_map) do
    case Map.get(unit_map, ingredient_user_meal.measurement_unit_id) do
      name when is_binary(name) and name != "" -> name
      _ -> Mehungry.Food.RecipeIngredient.unit_label(ingredient_user_meal)
    end
  end

  # The translated recipe title when a translation with a non-blank title exists,
  # otherwise the recipe's own (source-language) title.
  defp localized_recipe_title(_recipe, %Mehungry.AI.Bot.RecipeTranslation{title: title})
       when is_binary(title) and title != "",
       do: title

  defp localized_recipe_title(recipe, _translation), do: recipe.title

  # `free_food_user_meals` was added after the calendar shipped; tolerate meals
  # whose association isn't loaded (older preload paths) by treating them as none.
  defp free_food_user_meals(%{free_food_user_meals: %Ecto.Association.NotLoaded{}}), do: []
  defp free_food_user_meals(%{free_food_user_meals: ffms}) when is_list(ffms), do: ffms
  defp free_food_user_meals(_), do: []

  def list_history_user_meals_for_user(user_id, date) do
    {:ok, day_start} = NaiveDateTime.from_iso8601(date <> " 00:00:00")
    day_end = NaiveDateTime.add(day_start, 1, :day)

    query =
      from meal in UserMeal,
        where:
          meal.user_id == ^user_id and meal.start_dt >= ^day_start and
            meal.start_dt < ^day_end

    Repo.all(query)
    |> preload_calendar_meals()
  end

  def list_history_user_meals_for_user(user_id, start_dt, end_dt) do
    end_dt = NaiveDateTime.add(end_dt, 24, :hour)

    query =
      from meal in UserMeal,
        where:
          meal.user_id == ^user_id and ^start_dt <= meal.start_dt and
            (^end_dt >= meal.end_dt or is_nil(meal.end_dt))

    Repo.all(query)
    |> Repo.preload(
      recipe_user_meals: [
        recipe: [
          recipe_ingredients: [
            :measurement_unit,
            :ingredient_portion,
            ingredient: [:category, :ingredient_translation]
          ]
        ]
      ]
    )
  end

  @doc """
  A user's `UserMeal`s whose `start_dt` falls on any day in the inclusive
  `start_date..end_date` span, preloaded deeply enough for blueprint
  compatibility analysis: each recipe's `recipe_ingredients` (with `ingredient`,
  for compound resolution) plus each logged ingredient's `ingredient` (with
  `ingredient_portions` + `ingredient_nutrients: [nutrient: :measurement_unit]`,
  which `MealBlueprints.PlanCompatibility` reads to compute calories).

  Used by `Mehungry.MealBlueprints.calendar_progress/3` to measure a calendar
  week against a blueprint's targets.
  """
  def list_user_meals_in_range(user_id, %Date{} = start_date, %Date{} = end_date) do
    range_start = NaiveDateTime.new!(start_date, ~T[00:00:00])
    range_end = NaiveDateTime.new!(end_date, ~T[23:59:59])

    query =
      from meal in UserMeal,
        where:
          meal.user_id == ^user_id and meal.start_dt >= ^range_start and
            meal.start_dt <= ^range_end

    Repo.all(query)
    |> Repo.preload(
      recipe_user_meals: [
        recipe: [
          recipe_ingredients: [
            :measurement_unit,
            :ingredient_portion,
            ingredient: [:category, :ingredient_translation]
          ]
        ]
      ],
      ingredient_user_meals: [
        :measurement_unit,
        ingredient_portion: :measurement_unit,
        ingredient: [
          :category,
          :ingredient_translation,
          :ingredient_portions,
          ingredient_nutrients: [nutrient: :measurement_unit]
        ]
      ],
      free_food_user_meals: []
    )
  end

  @doc """
  Gets a single user_meal.

  Raises `Ecto.NoResultsError` if the User meal does not exist.

  ## Examples

      iex> get_user_meal!(123)
      %UserMeal{}

      iex> get_user_meal!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user_meal!(id) do
    Repo.get!(UserMeal, id)
    |> Repo.preload(
      recipe_user_meals: [
        recipe: [
          recipe_ingredients: [
            :measurement_unit,
            :ingredient_portion,
            ingredient: [:category, :ingredient_translation]
          ]
        ]
      ]
    )
  end

  @doc """
  Gets a single user_meal owned by `user_id`.

  Scopes the lookup by owner so a meal id belonging to another user raises
  `Ecto.NoResultsError` instead of leaking/mutating that user's data.
  """
  def get_user_meal!(user_id, id) do
    from(m in UserMeal, where: m.id == ^id and m.user_id == ^user_id)
    |> Repo.one!()
    |> Repo.preload(
      recipe_user_meals: [
        recipe: [
          recipe_ingredients: [
            :measurement_unit,
            :ingredient_portion,
            ingredient: [:category, :ingredient_translation]
          ]
        ]
      ]
    )
  end

  def get_user_meal_raw!(id) do
    Repo.get!(UserMeal, id)
    |> Repo.preload(
      consume_recipe_user_meals: [recipe_user_meal: :recipe],
      recipe_user_meals: [
        :recipe
      ],
      ingredient_user_meals: [
        :ingredient
      ]
    )
  end

  @doc """
  Gets a single user_meal owned by `user_id`, with the raw associations used by
  the edit form. Scoped by owner (see `get_user_meal!/2`).
  """
  def get_user_meal_raw!(user_id, id) do
    from(m in UserMeal, where: m.id == ^id and m.user_id == ^user_id)
    |> Repo.one!()
    |> Repo.preload(
      consume_recipe_user_meals: [recipe_user_meal: :recipe],
      recipe_user_meals: [
        :recipe
      ],
      ingredient_user_meals: [
        :ingredient
      ]
    )
  end

  @doc """
  Creates a user_meal.

  ## Examples

      iex> create_user_meal(%{field: value})
      {:ok, %UserMeal{}}

      iex> create_user_meal(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_user_meal(attrs \\ %{}) do
    %UserMeal{}
    |> UserMeal.changeset(attrs)
    |> Repo.insert()
    |> maybe_put_ingredient_nutrients()
  end

  @doc """
  Clones an existing meal (owned by `user_id`) onto `target_date`, copying its
  recipe / ingredient / free-food children verbatim and keeping the same
  `meal_type`, `title`, and time-of-day. The "log again" shortcut for repetitive
  eaters — re-logging a meal is one tap instead of rebuilding it by hand.

  Returns `{:ok, %UserMeal{}}` or `{:error, changeset}`; raises
  `Ecto.NoResultsError` if the meal isn't the user's.
  """
  def duplicate_user_meal(user_id, meal_id, %Date{} = target_date) do
    source =
      from(m in UserMeal, where: m.id == ^meal_id and m.user_id == ^user_id)
      |> Repo.one!()
      |> Repo.preload([:recipe_user_meals, :ingredient_user_meals, :free_food_user_meals])

    create_user_meal(%{
      user_id: user_id,
      title: source.title,
      meal_type: source.meal_type,
      start_dt: move_to_date(source.start_dt, target_date),
      end_dt: move_to_date(source.end_dt, target_date),
      recipe_user_meals:
        Enum.map(source.recipe_user_meals, fn r ->
          %{
            recipe_id: r.recipe_id,
            cooking: r.cooking,
            cooking_portions: r.cooking_portions,
            consume_portions: r.consume_portions
          }
        end),
      ingredient_user_meals:
        Enum.map(source.ingredient_user_meals, fn i ->
          %{
            ingredient_id: i.ingredient_id,
            quantity: i.quantity,
            measurement_unit_id: i.measurement_unit_id,
            ingredient_portion_id: i.ingredient_portion_id
          }
        end),
      free_food_user_meals:
        Enum.map(source.free_food_user_meals, fn f ->
          %{
            name: f.name,
            grams: f.grams,
            nutrients_per_100g: f.nutrients_per_100g,
            portion_name: f.portion_name,
            portion_grams: f.portion_grams,
            portions: f.portions
          }
        end)
    })
  end

  # Moves a naive datetime onto `date`, preserving its time-of-day; a nil source
  # datetime lands at noon so the cloned meal still sorts into the target day.
  defp move_to_date(%NaiveDateTime{} = dt, %Date{} = date),
    do: NaiveDateTime.new!(date, NaiveDateTime.to_time(dt))

  defp move_to_date(_nil, %Date{} = date), do: NaiveDateTime.new!(date, ~T[12:00:00])

  @doc """
  Updates a user_meal.

  ## Examples

      iex> update_user_meal(user_meal, %{field: new_value})
      {:ok, %UserMeal{}}

      iex> update_user_meal(user_meal, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_meal(%UserMeal{} = user_meal, attrs) do
    user_meal
    |> UserMeal.changeset(attrs)
    |> Repo.update()
    |> maybe_put_ingredient_nutrients()
  end

  # After a successful meal write, (re)compute and persist the denormalized
  # nutrient tree on each of its `ingredient_user_meals` so the calendar reads a
  # stored map instead of rebuilding it per ingredient on every load. Synchronous
  # (a single ingredient's tree is cheap and the calendar reloads immediately
  # after save) and best-effort — a computation failure must never fail the user's
  # save; the next edit or `start_ingredient_nutrient_backfill/0` repairs it.
  defp maybe_put_ingredient_nutrients({:ok, %UserMeal{} = meal}) do
    try do
      put_ingredient_user_meal_nutrients(meal.id)
    rescue
      e -> Logger.warning("Failed to store ingredient-meal nutrients for meal #{meal.id}: #{inspect(e)}")
    end

    {:ok, meal}
  end

  defp maybe_put_ingredient_nutrients(other), do: other

  @doc """
  Computes and persists the denormalized `nutrients` tree on every
  `IngredientUserMeal` of the given user meal (or a single `IngredientUserMeal`
  id). Loads the heavy `ingredient` preload (the only place it is still needed)
  and reuses `scaled_ingredient_nutrient_tree/2` so the stored map is byte-for-byte
  what the old read-time path produced.
  """
  def put_ingredient_user_meal_nutrients(user_meal_id) do
    gram_ids = NutrientCalculation.gram_unit_ids()

    from(ium in IngredientUserMeal, where: ium.user_meal_id == ^user_meal_id)
    |> Repo.all()
    |> Repo.preload(
      ingredient: [:ingredient_portions, ingredient_nutrients: [nutrient: :measurement_unit]]
    )
    |> Enum.each(fn ium ->
      tree = scaled_ingredient_nutrient_tree(ium, gram_ids)

      ium
      |> Ecto.Changeset.change(nutrients: tree)
      |> Repo.update()
    end)

    :ok
  end

  @doc """
  Enqueues one `IngredientUserMealPutNutrientsWorker` per existing
  `IngredientUserMeal` to backfill the denormalized `nutrients` column (for rows
  that predate the write-time hook). Mirrors
  `Food.Nutrients.enqueue_nutrient_recalculation_for_all/0`. Returns the number of
  jobs enqueued. Run this (and let the `:default` queue drain) before switching the
  calendar read path to the stored column.
  """
  def start_ingredient_nutrient_backfill do
    ids = Repo.all(from ium in IngredientUserMeal, select: ium.id)

    Enum.each(ids, fn id ->
      %{ingredient_user_meal_id: id}
      |> Mehungry.IngredientUserMealPutNutrientsWorker.new()
      |> Oban.insert()
    end)

    length(ids)
  end

  @doc """
  Deletes a user_meal.

  ## Examples

      iex> delete_user_meal(user_meal)
      {:ok, %UserMeal{}}

      iex> delete_user_meal(user_meal)
      {:error, %Ecto.Changeset{}}

  """
  def delete_user_meal(%UserMeal{} = user_meal) do
    Repo.delete(user_meal)
  end

  @doc """
  Deletes every one of `user_id`'s `UserMeal`s whose `start_dt` falls on any day
  in the inclusive `start_date..end_date` span (used to clear a week before a
  meal-plan import overwrites it). Child `recipe_user_meals`/`ingredient_user_meals`
  cascade at the DB level; `consume_recipe_user_meals` have no FK cascade, so they
  are removed first inside the same transaction. Returns the number of meals deleted.
  """
  def delete_user_meals_in_date_range(user_id, %Date{} = start_date, %Date{} = end_date) do
    range_start = NaiveDateTime.new!(start_date, ~T[00:00:00])
    range_end = NaiveDateTime.new!(end_date, ~T[23:59:59])

    ids_query =
      from m in UserMeal,
        where:
          m.user_id == ^user_id and m.start_dt >= ^range_start and
            m.start_dt <= ^range_end,
        select: m.id

    {:ok, count} =
      Repo.transaction(fn ->
        ids = Repo.all(ids_query)

        from(c in ConsumeRecipeUserMeal, where: c.user_meal_id in ^ids)
        |> Repo.delete_all()

        {deleted, _} = from(m in UserMeal, where: m.id in ^ids) |> Repo.delete_all()
        deleted
      end)

    count
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user_meal changes.

  ## Examples

      iex> change_user_meal(user_meal)
      %Ecto.Changeset{data: %UserMeal{}}

  """
  def change_user_meal(%UserMeal{} = user_meal, attrs \\ %{}) do
    UserMeal.changeset(user_meal, attrs)
  end

  ## ----------------------------------- Day notes ------------------------------------------

  alias Mehungry.History.DayNote

  @doc """
  The user's note for a single day, or `nil` when none exists.
  """
  def get_day_note(user_id, %Date{} = date) do
    Repo.get_by(DayNote, user_id: user_id, date: date)
  end

  @doc """
  All of a user's day notes in `[first, last]` as a `%{Date => body}` map, so the
  calendar can load a whole week's notes in one query (no N+1 over the 7 days).
  """
  def list_day_notes(user_id, %Date{} = first, %Date{} = last) do
    DayNote
    |> where([n], n.user_id == ^user_id and n.date >= ^first and n.date <= ^last)
    |> Repo.all()
    |> Map.new(fn n -> {n.date, n.body} end)
  end

  @doc """
  Upserts the note for `(user_id, date)`. A blank/nil body deletes the row rather
  than storing an empty note, so clearing a note tidies up after itself. Returns
  `{:ok, %DayNote{}}`, `{:ok, nil}` (deleted/no-op), or `{:error, changeset}`.
  """
  def upsert_day_note(user_id, %Date{} = date, body) do
    existing = get_day_note(user_id, date)

    case {existing, blank?(body)} do
      {nil, true} ->
        {:ok, nil}

      {%DayNote{} = note, true} ->
        {:ok, _} = Repo.delete(note)
        {:ok, nil}

      {nil, false} ->
        %DayNote{}
        |> DayNote.changeset(%{user_id: user_id, date: date, body: body})
        |> Repo.insert()

      {%DayNote{} = note, false} ->
        note
        |> DayNote.changeset(%{body: body})
        |> Repo.update()
    end
  end

  defp blank?(nil), do: true
  defp blank?(body) when is_binary(body), do: String.trim(body) == ""
  defp blank?(_), do: false
end
