defmodule Mehungry.Food.NutrientCalculation do
  @moduledoc """
  Calculates complete nutritional information for a recipe by summing
  scaled per-ingredient nutrient amounts.

  ## How the math works

  USDA FoodData Central stores every nutrient amount **per 100 g** of the
  ingredient.  `IngredientPortion` stores the gram equivalent for a given
  measurement unit (e.g. 1 cup = 240 g).  The scaling factor per ingredient is:

      scaling_factor = total_grams_in_recipe / 100.0
      scaled_nutrient = usda_amount_per_100g × scaling_factor

  where `total_grams_in_recipe = quantity × grams_per_unit`.

  ## Assumptions

  * `IngredientPortion.gram_weight` holds **grams for `amount` units** of the
    associated MeasurementUnit.  Dividing by `amount` (default 1.0 when nil)
    gives the true grams-per-one-unit.
  * All gram-family units (name "g", "gram", "grammar"; alternate_name "g")
    are treated directly as grams — no portion lookup is needed.
  * USDA nutrients are provided in their raw units (kcal, g, mg, µg).
    The scaling factor is dimensionless (g / 100 g), so the unit is preserved.

  ## Failure handling

  Call `validate_ingredient_units/1` before saving a recipe to surface
  missing portions as user-visible changeset errors.  If an unknown unit
  somehow reaches the calculation layer (e.g. via a direct DB update), the
  ingredient contributes 0 g to avoid silently inflating nutrient totals.
  """

  require Logger

  alias Mehungry.Food.NutrientNameNormalizer
  alias Mehungry.Food.NutrientHierarchyBuilder

  import Ecto.Query
  alias Mehungry.Repo

  # ─────────────────────────────────────────────────────────────────────────
  # Constants
  # ─────────────────────────────────────────────────────────────────────────

  # Preferred energy entry when an ingredient has both calculation methods.
  @specific "Energy (Atwater Specific Factors)"
  # Fallback energy entry used when Specific Factors are absent.
  @general "Energy (Atwater General Factors)"

  # ═════════════════════════════════════════════════════════════════════════
  # PUBLIC API
  # ═════════════════════════════════════════════════════════════════════════

  @doc """
  Main entry point.

  Returns `{primary_size, [nutrient]}` where the nutrient list is the
  priority-sorted hierarchical output of `NutrientHierarchyBuilder`.
  Returns `{0, []}` for a recipe with no ingredients.
  """
  def calculate_recipe_nutrition_value(recipe) do
    recipe_ingredients = get_value(recipe, :recipe_ingredients)

    if is_nil(recipe_ingredients) or recipe_ingredients == [] do
      {0, []}
    else
      ingredients = map_ingredients_to_structured_form(recipe_ingredients)
      result = calculate_nutrition_for_recipe(ingredients)
      {8, Map.get(result, :structured_nutrients)}
    end
  end

  @doc """
  Validates that every recipe ingredient has a resolvable unit-to-gram mapping
  before the recipe is persisted.

  Accepts a list of maps with `:ingredient_id` and `:measurement_unit_id` keys.
  Gram-family units (g, gram, grammar, alternate_name "g") are always accepted
  without a portion entry.

  Returns `:ok` or `{:error, [%{ingredient_name: string, unit_name: string}]}`
  listing every ingredient/unit pair that lacks an `IngredientPortion` row.
  """
  def validate_ingredient_units(ingredient_params) do
    gram_ids = load_gram_unit_ids()

    # Gram-family units never need a portion — skip them immediately.
    to_check =
      Enum.reject(ingredient_params, fn p ->
        MapSet.member?(gram_ids, p.measurement_unit_id)
      end)

    if to_check == [] do
      :ok
    else
      ingredient_ids = Enum.map(to_check, & &1.ingredient_id)
      unit_ids = Enum.map(to_check, & &1.measurement_unit_id)

      ingredients =
        Repo.all(
          from i in Mehungry.Food.Ingredient,
            where: i.id in ^ingredient_ids,
            preload: [:ingredient_portions]
        )

      units = Repo.all(from m in Mehungry.Food.MeasurementUnit, where: m.id in ^unit_ids)

      ingredients_by_id = Map.new(ingredients, &{&1.id, &1})
      units_by_id = Map.new(units, &{&1.id, &1})

      missing =
        Enum.reject(to_check, fn params ->
          ingredient = Map.get(ingredients_by_id, params.ingredient_id)

          ingredient &&
            Enum.any?(ingredient.ingredient_portions, fn portion ->
              portion.measurement_unit_id == params.measurement_unit_id
            end)
        end)

      if missing == [] do
        :ok
      else
        errors =
          Enum.map(missing, fn params ->
            ingredient = Map.get(ingredients_by_id, params.ingredient_id)
            unit = Map.get(units_by_id, params.measurement_unit_id)

            %{
              ingredient_name: (ingredient && ingredient.name) || "unknown",
              unit_name: (unit && unit.name) || "unknown"
            }
          end)

        {:error, errors}
      end
    end
  end

  # ═════════════════════════════════════════════════════════════════════════
  # INGREDIENT → GRAM CONVERSION
  # ═════════════════════════════════════════════════════════════════════════

  @doc """
  Loads all recipe ingredients from the DB (with their nutrient data and
  portions) and converts each one into a structured map for aggregation.

  Each returned map contains:
  * `:ingredient` — the loaded Ingredient struct
  * `:gram_weight` — total grams contributed by this ingredient entry
  * `:nutrients` — scaled nutrient list from `build_nutrient_list/2`
  """
  def map_ingredients_to_structured_form(recipe_ingredient_params) do
    gram_unit_ids = load_gram_unit_ids()

    ingredient_ids = Enum.map(recipe_ingredient_params, & &1.ingredient_id)

    ingredients =
      Repo.all(
        from i in Mehungry.Food.Ingredient,
          where: i.id in ^ingredient_ids,
          preload: [
            :ingredient_portions,
            ingredient_nutrients: [nutrient: :measurement_unit]
          ]
      )

    ingredients_by_id = Map.new(ingredients, &{&1.id, &1})

    Enum.map(recipe_ingredient_params, fn params ->
      ingredient = Map.fetch!(ingredients_by_id, params.ingredient_id)
      ingredient_portion_id = Map.get(params, :ingredient_portion_id)

      gram_weight =
        calculate_gram_weight(
          ingredient,
          params.measurement_unit_id,
          ingredient_portion_id,
          params.quantity,
          gram_unit_ids
        )

      %{
        quantity: params.quantity,
        measurement_unit_id: params.measurement_unit_id,
        ingredient_portion_id: ingredient_portion_id,
        ingredient: ingredient,
        nutrients: build_nutrient_list(ingredient, gram_weight),
        gram_weight: gram_weight
      }
    end)
  end

  @doc """
  Converts a recipe ingredient's `quantity` into total grams.

  Resolution order:
  1. If the unit is a gram-family unit, `quantity` is already in grams.
  2. Use the recipe ingredient's own `ingredient_portion_id` when set (the
     portion selected at save time — this is the authoritative link and also
     resolves description-only portions whose `measurement_unit_id` is nil).
  3. Otherwise fall back to the ingredient's `IngredientPortion` for this unit.
  4. Compute `quantity × (gram_weight / amount)` for the resolved portion.
  5. If none resolves (and the unit is not a gram unit), log a warning and
     return 0.0.  `validate_ingredient_units/1` should prevent this during
     normal recipe creation.

  The `amount` field on `IngredientPortion` is the USDA serving denominator.
  USDA Foundation Foods almost always sets `amount = 1.0`, but when it differs
  (e.g. `amount = 0.5` and `gram_weight = 120` meaning "half cup = 120 g"),
  dividing restores the correct grams-per-one-unit (240 g/cup).
  Nil `amount` is treated as 1.0.
  """
  def calculate_gram_weight(
        ingredient,
        measurement_unit_id,
        ingredient_portion_id,
        quantity,
        gram_unit_ids
      ) do
    quantity_float = safe_to_float(quantity)
    portions = ingredient.ingredient_portions || []

    portion =
      if ingredient_portion_id do
        Enum.find(portions, fn p -> p.id == ingredient_portion_id end)
      end || Enum.find(portions, fn p -> p.measurement_unit_id == measurement_unit_id end)

    cond do
      MapSet.member?(gram_unit_ids, measurement_unit_id) ->
        quantity_float

      portion && portion.gram_weight ->
        amount = safe_to_float(portion.amount || 1.0)

        grams_per_unit =
          if amount > 0, do: portion.gram_weight / amount, else: portion.gram_weight

        quantity_float * grams_per_unit

      true ->
        Logger.warning(
          "NutrientCalculation: no portion found for ingredient #{ingredient.id} " <>
            "with measurement_unit_id #{measurement_unit_id}; contributing 0 g"
        )

        0.0
    end
  end

  # ═════════════════════════════════════════════════════════════════════════
  # NUTRIENT LIST BUILDING
  # ═════════════════════════════════════════════════════════════════════════

  @doc """
  Builds the scaled nutrient list for a single ingredient given its total gram
  weight in the recipe.

  Scaling formula: `usda_amount_per_100g × (gram_weight / 100.0)`.

  Energy duplicates are removed first so calories are not double-counted
  (see `filter_energy_duplicates/1`).
  """
  def build_nutrient_list(ingredient, gram_weight) do
    scaling_factor = safe_to_float(gram_weight) / 100.0

    ingredient.ingredient_nutrients
    |> filter_energy_duplicates()
    |> Enum.map(fn nutrient_entry ->
      amount = safe_nutrient_amount(nutrient_entry.amount)

      nutrient_name =
        case nutrient_entry.nutrient do
          %{name: name} when is_binary(name) -> name
          %{name: name} when is_atom(name) -> Atom.to_string(name)
          _ -> "Unknown"
        end

      unit_name =
        case nutrient_entry.nutrient do
          %{measurement_unit: %{name: name}} when is_binary(name) -> name
          %{measurement_unit: %{name: name}} when is_atom(name) -> Atom.to_string(name)
          %{measurement_unit: %{alternate_name: name}} when is_binary(name) -> name
          _ -> "g"
        end

      nutrient_number =
        case nutrient_entry.nutrient do
          %{number: num} when is_binary(num) -> num
          %{number: num} when is_integer(num) -> Integer.to_string(num)
          _ -> nil
        end

      %{
        name: nutrient_name,
        amount: amount * scaling_factor,
        measurement_unit: unit_name,
        nutrient_id: nutrient_entry.nutrient_id,
        nutrient_number: nutrient_number
      }
    end)
  end

  @doc """
  Removes duplicate energy entries for a single ingredient's nutrient list.

  USDA data includes multiple energy entries per ingredient:
  "Energy" (kcal, ref 1008), "Energy" (kJ, ref 1062),
  "Energy (Atwater General Factors)" (ref 2047), and
  "Energy (Atwater Specific Factors)" (ref 2048).

  All four have different reference_ids so grouping by reference_id kept
  every entry, then NutrientNameNormalizer collapsed them all into one
  "Energy" key and summed them — inflating calories 3-4×.

  Fix: split energy vs non-energy across the whole list, then pick exactly
  one energy entry per ingredient.  Priority: Atwater Specific > Atwater
  General > any kcal entry > first found.
  """
  def filter_energy_duplicates(nutrients) do
    {energy_nutrients, other_nutrients} =
      Enum.split_with(nutrients, fn entry ->
        case entry.nutrient do
          %{name: name} when is_binary(name) -> String.starts_with?(name, "Energy")
          _ -> false
        end
      end)

    selected_energy =
      cond do
        specific = find_energy(energy_nutrients, @specific) ->
          [specific]

        general = find_energy(energy_nutrients, @general) ->
          [general]

        kcal =
            Enum.find(energy_nutrients, fn e ->
              e.nutrient.name == "Energy" and
                  match?(%{name: "kilocalorie"}, e.nutrient.measurement_unit)
            end) ->
          [kcal]

        energy_nutrients != [] ->
          [hd(energy_nutrients)]

        true ->
          []
      end

    other_nutrients ++ selected_energy
  end

  # ═════════════════════════════════════════════════════════════════════════
  # RECIPE-LEVEL AGGREGATION
  # ═════════════════════════════════════════════════════════════════════════

  @doc """
  Aggregates scaled per-ingredient nutrients into the recipe's total nutrition.

  Steps:
  1. Flatten all per-ingredient nutrient lists into a single stream.
  2. Group by normalised name (via `NutrientNameNormalizer`) and sum amounts.
  3. Build a hierarchical structure (fats → sub-fats, vitamins, minerals, etc.)
     via `NutrientHierarchyBuilder`.
  4. Sort the top-level map by display priority.

  Returns a map with `:flat_nutrients`, `:structured_nutrients`,
  `:total_calories`, and `:ingredient_count`.
  """
  def calculate_nutrition_for_recipe(ingredients_with_nutrients) do
    all_nutrients = Enum.flat_map(ingredients_with_nutrients, & &1.nutrients)

    grouped_nutrients =
      Enum.reduce(all_nutrients, %{}, fn nutrient, acc ->
        normalized_name = NutrientNameNormalizer.normalize(nutrient.name)

        existing =
          Map.get(acc, normalized_name, %{
            name: normalized_name,
            amount: 0.0,
            measurement_unit: nutrient.measurement_unit,
            nutrient_id: nutrient.nutrient_id,
            children: []
          })

        Map.put(acc, normalized_name, %{
          existing
          | amount: existing.amount + (nutrient.amount || 0.0)
        })
      end)
      |> Map.values()

    structured_nutrients =
      grouped_nutrients
      |> NutrientHierarchyBuilder.build_hierarchy()
      |> sort_nutrients_by_priority()

    %{
      flat_nutrients: grouped_nutrients,
      structured_nutrients: structured_nutrients,
      total_calories: calculate_total_calories(grouped_nutrients),
      ingredient_count: length(ingredients_with_nutrients)
    }
  end

  @doc """
  Sorts the hierarchical nutrient map into a priority-ordered list for display.

  Priority: Energy → Protein → Total Fat → Vitamins → Carbohydrates →
  Fiber → Total Sugars → Minerals → everything else (999).

  Keys are atoms because `NutrientHierarchyBuilder.convert_to_atom_keys/1`
  converts them on output. The keys used here are the actual top-level keys
  `build_result/1` emits: lowercase group keys (`:total_fat`,
  `:total_carbohydrates`, `:vitamins`, `:minerals`) and title-case main
  nutrients (`:Energy`, `:Protein`). Fiber and sugars are nested under
  `:total_carbohydrates`, so they never appear at the top level and aren't
  listed here.
  """
  def sort_nutrients_by_priority(nutrient_map) when is_map(nutrient_map) do
    priority_order = %{
      :Energy => 1,
      :Protein => 2,
      :total_fat => 3,
      :vitamins => 4,
      :total_carbohydrates => 5,
      :minerals => 6
    }

    nutrient_map
    |> Enum.filter(fn {_name, nutrient} -> not is_nil(nutrient) end)
    |> Enum.sort_by(fn {name, _nutrient} -> {Map.get(priority_order, name, 999), name} end)
    |> Enum.map(fn {_name, nutrient} -> nutrient end)
  end

  @doc """
  Extracts total calories from the flat nutrient list.

  Returns the `Energy` nutrient's amount rounded to zero decimal places,
  or 0 if no Energy entry is present.
  """
  def calculate_total_calories(nutrients) do
    case Enum.find(nutrients, fn nutrient -> nutrient.name == "Energy" end) do
      nil -> 0
      energy -> Float.round(energy.amount, 0)
    end
  end

  # ═════════════════════════════════════════════════════════════════════════
  # UTILITIES
  # ═════════════════════════════════════════════════════════════════════════

  @doc "Safely converts any value to a float. Returns 0.0 for nil or unparseable strings."
  def safe_to_float(value) when is_float(value), do: value
  def safe_to_float(value) when is_integer(value), do: value * 1.0

  def safe_to_float(value) when is_binary(value) do
    case Float.parse(value) do
      {float, _} -> float
      :error -> 0.0
    end
  end

  def safe_to_float(_), do: 0.0

  @doc "Coerces a nutrient amount to float. Returns 0.0 for nil or non-numeric values."
  def safe_nutrient_amount(amount) when is_float(amount), do: amount
  def safe_nutrient_amount(amount) when is_integer(amount), do: amount * 1.0
  def safe_nutrient_amount(_), do: 0.0

  @doc "Fetches a value from a map accepting both atom and string versions of the key."
  def get_value(map, key) do
    get_value_specific(map, key) || get_value_specific(map, Atom.to_string(key))
  end

  def get_value_specific(map, key) when is_atom(key), do: map[key] || map[to_string(key)]
  def get_value_specific(map, key) when is_binary(key), do: map[key] || map[String.to_atom(key)]

  # ═════════════════════════════════════════════════════════════════════════
  # PRIVATE
  # ═════════════════════════════════════════════════════════════════════════

  defp find_energy(nutrients, target_name) do
    Enum.find(nutrients, fn nutrient -> nutrient.nutrient.name == target_name end)
  end

  @doc """
  Public accessor for the gram-family MeasurementUnit id set, so read paths
  (e.g. the calendar's per-ingredient nutrient scaling) can resolve grams once
  and reuse the set across many `calculate_gram_weight/5` calls.
  """
  def gram_unit_ids, do: load_gram_unit_ids()

  # Returns a MapSet of all MeasurementUnit IDs that represent grams.
  # Matches by name ("g", "gram", "grammar") or alternate_name ("g") to
  # handle units created by both the USDA importer and the mass backfill script.
  defp load_gram_unit_ids do
    Repo.all(
      from m in Mehungry.Food.MeasurementUnit,
        where: m.alternate_name == "g" or m.name in ["g", "gram", "grammar"]
    )
    |> MapSet.new(& &1.id)
  end

  # ─────────────────────────────────────────────────────────────────────────
  # Debug helpers (dev / IEx only)
  # ─────────────────────────────────────────────────────────────────────────

  def pretty_print_nutrition(nutrition_result) do
    IO.puts("\n" <> String.duplicate("=", 50))
    IO.puts("Total Calories: #{Float.round(nutrition_result.total_calories, 0)} kcal")
    IO.puts("Number of Ingredients: #{nutrition_result.ingredient_count}")
    IO.puts("")
    print_nutrients(nutrition_result.structured_nutrients, 0)
    IO.puts(String.duplicate("=", 50))
  end

  defp print_nutrients([], _level), do: :ok

  defp print_nutrients([nutrient | rest], level) do
    indent = String.duplicate("  ", level)
    amount = Float.round(nutrient.amount, 1)
    IO.puts("#{indent}• #{nutrient.name}: #{amount} #{nutrient.measurement_unit}")

    if nutrient.children && length(nutrient.children) > 0,
      do: print_nutrients(nutrient.children, level + 1)

    print_nutrients(rest, level)
  end
end
