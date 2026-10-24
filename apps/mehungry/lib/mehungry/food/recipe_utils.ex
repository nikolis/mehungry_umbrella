defmodule Mehungry.Food.RecipeUtils do
  @moduledoc """
  Small display helpers for a recipe's **already-computed** nutrient map.

  The authoritative nutrition *calculation* now lives in
  `Mehungry.Food.NutrientCalculation` (invoked at write time via
  `Mehungry.RecipePutNutrientsWorker` and persisted onto `recipe.nutrients`).
  The per-meal/day aggregation lives in
  `Mehungry.NutrientUtils.summarize_meals_nutrients/1`.

  What remains here is the view-only `sort_nutrients_from_db/1` helper the
  calendar widget uses to order a stored `recipe.nutrients` map for rendering.
  The old on-the-fly recomputation path (`get_nutrients/1`, `adjust_amount/4`,
  `calculate_nutrition_for_recipe_ingredient*/1`, …) was dead and has been
  removed — see `docs/food/nutrition_calculation.md`.
  """

  @doc """
  Sorts a `{name, nutrient}` list so the entries most people care about float to
  the top (Energy, Total lipid, Carbohydrate, Protein, Fiber, Sugar, Vitamins),
  then everything else in its original order. Returns the list zipped with its
  index (`Enum.with_index/1`).
  """
  def sort_nutrients_from_db(nutrients) do
    carb = Enum.find(nutrients, fn {name, _x} -> String.contains?(name, "Carbohydrate") end)
    protein = Enum.find(nutrients, fn {name, _x} -> String.contains?(name, "Protein") end)
    fiber = Enum.find(nutrients, fn {name, _x} -> String.contains?(name, "Fiber") end)
    fat = Enum.find(nutrients, fn {name, _x} -> String.contains?(name, "Total lipid") end)
    sugar = Enum.find(nutrients, fn {name, _x} -> String.contains?(name, "Sugar") end)
    energy = Enum.find(nutrients, fn {name, _x} -> String.contains?(name, "Energy") end)
    vitamins = Enum.find(nutrients, fn {name, _x} -> String.contains?(name, "Vitamins") end)

    primaries = [energy, fat, carb, protein, fiber, sugar, vitamins]
    primaries = Enum.filter(primaries, fn x -> !is_nil(x) end)
    nutrients = Enum.filter(nutrients, fn x -> x not in primaries end)
    Enum.with_index(primaries ++ nutrients)
  end
end
