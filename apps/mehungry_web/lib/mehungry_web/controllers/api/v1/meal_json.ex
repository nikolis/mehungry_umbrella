defmodule MehungryWeb.Api.V1.MealJSON do
  @moduledoc "Serializers for the meal planner / calendar (spec §9)."

  import MehungryWeb.Api.V1.JSON.Helpers

  alias Mehungry.History
  alias Mehungry.History.IngredientUserMeal
  alias Mehungry.History.MealType
  alias Mehungry.NutrientUtils

  @doc "A weekly range grouped into days + the meal-type vocabulary."
  def range(meals, start_date, end_date) do
    icons = icon_map(meals)
    summaries = nutrition_summaries(meals)

    days =
      meals
      |> Enum.group_by(&NaiveDateTime.to_date(&1.start_dt))
      |> Enum.sort_by(fn {date, _} -> date end, Date)
      |> Enum.map(fn {date, day_meals} ->
        %{date: Date.to_iso8601(date), meals: Enum.map(day_meals, &meal(&1, icons, summaries))}
      end)

    data(%{
      range: %{start: Date.to_iso8601(start_date), end: Date.to_iso8601(end_date)},
      days: days,
      meal_type_vocabulary: vocabulary()
    })
  end

  @doc "A single day's meals."
  def day(meals, date) do
    icons = icon_map(meals)
    summaries = nutrition_summaries(meals)
    data(%{date: date, meals: Enum.map(meals, &meal(&1, icons, summaries))})
  end

  @doc "A single meal."
  def meal(user_meal),
    do: meal(user_meal, icon_map([user_meal]), nutrition_summaries([user_meal]))

  def meal(user_meal, icons, summaries) do
    %{
      id: user_meal.id,
      title: user_meal.title,
      meal_type: user_meal.meal_type,
      start_dt: naive(user_meal.start_dt),
      end_dt: naive(user_meal.end_dt),
      recipes: user_meal.recipe_user_meals |> loaded() |> Enum.map(&recipe_entry/1),
      ingredients:
        user_meal.ingredient_user_meals |> loaded() |> Enum.map(&ingredient_entry(&1, icons)),
      free_foods: user_meal.free_food_user_meals |> loaded() |> Enum.map(&free_food_entry/1),
      nutrition_summary: Map.get(summaries, user_meal.id)
    }
  end

  # A compact `%{meal_id => %{energy, protein, carbs, fat}}` summary for the whole
  # response, so the calendar overview surfaces (week strip, today band, weekly
  # average) can show kcal + macros straight from the `/meals` payload without a
  # second round-trip to `GET /meals/day/:date/nutrition` (spec §9).
  #
  # Computed off the already-loaded calendar preloads: `format_user_meals/1`
  # reads the denormalized nutrient columns (recipe/ingredient `nutrients`, scaled
  # free-food trees), so this adds no per-meal DB queries — only one batched icon
  # lookup shared across the set. Names are the canonical English buckets
  # `macro_summary/1` matches, so we summarize before any localization. Energy is
  # rounded to whole kcal and the macros to 0.1 g by `macro_summary/1`.
  defp nutrition_summaries(meals) do
    meals
    |> History.format_user_meals()
    |> Map.new(fn formatted ->
      macros =
        [formatted]
        |> NutrientUtils.summarize_meals_nutrients()
        |> NutrientUtils.macro_summary()

      {formatted.id,
       %{
         energy: macros.energy_kcal,
         protein: macros.protein_g,
         carbs: macros.carbs_g,
         fat: macros.fat_g
       }}
    end)
  end

  # One batched `%{ingredient_id => emoji}` for a whole response, so serializing
  # a day/week of meals adds a bounded number of queries, not one per ingredient
  # (see `Mehungry.Food.ingredient_icons/1`).
  defp icon_map(meals) do
    ids = for m <- meals, ium <- loaded(m.ingredient_user_meals), do: ium.ingredient_id
    Mehungry.Food.ingredient_icons(ids)
  end

  def vocabulary do
    Enum.map(MealType.values() ++ [nil], fn value ->
      %{key: value, label: MealType.label(value)}
    end)
  end

  defp recipe_entry(rum) do
    recipe = assoc(rum.recipe)

    %{
      recipe_id: rum.recipe_id,
      title: recipe && recipe.title,
      image_url: recipe && recipe.image_url,
      servings: rum.consume_portions,
      consumed: (loaded(rum.consume_recipe_user_meals) != [])
    }
  end

  defp ingredient_entry(ium, icons) do
    ingredient = assoc(ium.ingredient)
    mu = assoc(ium.measurement_unit)

    %{
      ingredient_id: ium.ingredient_id,
      name: ingredient && ingredient.name,
      icon: Map.get(icons, ium.ingredient_id),
      quantity: ium.quantity,
      # FKs + the signed picker value, so the client can round-trip an edit (or
      # pre-select the right `units` option) exactly like the calendar form.
      measurement_unit_id: ium.measurement_unit_id,
      ingredient_portion_id: ium.ingredient_portion_id,
      unit_selection: IngredientUserMeal.unit_selection_value(ium),
      measurement_unit: mu && %{id: mu.id, name: mu.name}
    }
  end

  defp free_food_entry(ff) do
    %{
      id: ff.id,
      name: ff.name,
      grams: ff.grams,
      portion_name: ff.portion_name,
      portion_grams: ff.portion_grams,
      portions: ff.portions,
      # Stored canonically as %{name => %{"unit","amount"}}; echo back as the
      # [{name,unit,amount}] list the client sent for lossless round-trip.
      nutrients_per_100g: per_100g_list(ff.nutrients_per_100g)
    }
  end

  defp per_100g_list(map) when is_map(map) do
    Enum.map(map, fn {name, v} ->
      %{name: name, unit: v["unit"], amount: v["amount"]}
    end)
  end

  defp per_100g_list(_), do: []

  defp assoc(%Ecto.Association.NotLoaded{}), do: nil
  defp assoc(value), do: value

  defp loaded(list) when is_list(list), do: list
  defp loaded(_), do: []
end
