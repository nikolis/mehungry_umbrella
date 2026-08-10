defmodule Mehungry.NutrientUtils do
  @moduledoc """
  Handles merging of USDA nutrient data with intelligent normalization.
  De-duplicates equivalent nutrients (e.g., different energy calculation methods).
  """

  # Master mapping of nutrient names to their canonical form
  @canonical_mapping %{
    # Energy variations
    "energy" => "Energy",
    "energy (atwater specific factors)" => "Energy",
    "energy (atwater general factors)" => "Energy",
    "energy (kcal)" => "Energy",
    "energy (j)" => "Energy",
    "calories" => "Energy",

    # Protein variations
    "protein" => "Protein",
    "protein (n x 6.25)" => "Protein",
    "protein (n x 5.70)" => "Protein",
    "protein (n x 5.83)" => "Protein",
    "protein (n x 6.38)" => "Protein",
    "crude protein" => "Protein",

    # Fat variations
    "total lipid (fat)" => "Total Fat",
    "total fat" => "Total Fat",
    "fat" => "Total Fat",
    "lipid" => "Total Fat",
    "total lipid" => "Total Fat",

    # Carbohydrate variations
    "carbohydrate" => "Carbohydrates",
    "carbohydrate (by difference)" => "Carbohydrates",
    "total carbohydrate" => "Carbohydrates",
    "carbs" => "Carbohydrates",

    # Fiber variations
    "fiber" => "Fiber",
    "total dietary fiber" => "Fiber",
    "dietary fiber" => "Fiber",
    "crude fiber" => "Fiber",
    "insoluble fiber" => "Fiber",
    "soluble fiber" => "Fiber",

    # Sugar variations
    "sugars" => "Total Sugars",
    "total sugars" => "Total Sugars",
    "sugar" => "Total Sugars",
    "added sugars" => "Added Sugars",
    "sucrose" => "Sugars",
    "glucose" => "Sugars",
    "fructose" => "Sugars",
    "lactose" => "Sugars",
    "maltose" => "Sugars",
    "galactose" => "Sugars",

    # Saturated Fat variations
    "saturated fat" => "Saturated Fat",
    "fatty acids, total saturated" => "Saturated Fat",
    "total saturated fatty acids" => "Saturated Fat",
    "sfa" => "Saturated Fat",

    # Monounsaturated Fat variations
    "monounsaturated fat" => "Monounsaturated Fat",
    "fatty acids, total monounsaturated" => "Monounsaturated Fat",
    "total monounsaturated fatty acids" => "Monounsaturated Fat",
    "mufa" => "Monounsaturated Fat",

    # Polyunsaturated Fat variations
    "polyunsaturated fat" => "Polyunsaturated Fat",
    "fatty acids, total polyunsaturated" => "Polyunsaturated Fat",
    "total polyunsaturated fatty acids" => "Polyunsaturated Fat",
    "pufa" => "Polyunsaturated Fat",

    # Cholesterol variations
    "cholesterol" => "Cholesterol",
    "total cholesterol" => "Cholesterol",

    # Sodium variations
    "sodium" => "Sodium",
    "na" => "Sodium",

    # Potassium variations
    "potassium" => "Potassium",
    "k" => "Potassium",

    # Calcium variations
    "calcium" => "Calcium",
    "ca" => "Calcium",

    # Iron variations
    "iron" => "Iron",
    "fe" => "Iron",

    # Magnesium variations
    "magnesium" => "Magnesium",
    "mg" => "Magnesium",

    # Phosphorus variations
    "phosphorus" => "Phosphorus",
    "p" => "Phosphorus",

    # Zinc variations
    "zinc" => "Zinc",
    "zn" => "Zinc",

    # Vitamin A variations
    "vitamin a" => "Vitamin A",
    "vitamin a (rae)" => "Vitamin A",
    "vitamin a (iu)" => "Vitamin A",
    "retinol" => "Vitamin A",
    "retinol activity equivalents" => "Vitamin A",

    # Vitamin C variations
    "vitamin c" => "Vitamin C",
    "ascorbic acid" => "Vitamin C",
    "total ascorbic acid" => "Vitamin C",

    # Vitamin D variations
    "vitamin d" => "Vitamin D",
    "vitamin d (d2 + d3)" => "Vitamin D",
    "cholecalciferol" => "Vitamin D",
    "ergocalciferol" => "Vitamin D",

    # Vitamin E variations
    "vitamin e" => "Vitamin E",
    "alpha-tocopherol" => "Vitamin E",
    "tocopherol" => "Vitamin E",

    # Vitamin K variations
    "vitamin k" => "Vitamin K",
    "phylloquinone" => "Vitamin K",

    # B Vitamin variations
    "thiamin" => "Vitamin B1 (Thiamin)",
    "thiamine" => "Vitamin B1 (Thiamin)",
    "vitamin b1" => "Vitamin B1 (Thiamin)",
    "riboflavin" => "Vitamin B2 (Riboflavin)",
    "vitamin b2" => "Vitamin B2 (Riboflavin)",
    "niacin" => "Vitamin B3 (Niacin)",
    "vitamin b3" => "Vitamin B3 (Niacin)",
    "pantothenic acid" => "Vitamin B5 (Pantothenic Acid)",
    "vitamin b5" => "Vitamin B5 (Pantothenic Acid)",
    "vitamin b6" => "Vitamin B6",
    "pyridoxine" => "Vitamin B6",
    "biotin" => "Vitamin B7 (Biotin)",
    "vitamin b7" => "Vitamin B7 (Biotin)",
    "folate" => "Vitamin B9 (Folate)",
    "folic acid" => "Vitamin B9 (Folate)",
    "dietary folate equivalent" => "Vitamin B9 (Folate)",
    "vitamin b9" => "Vitamin B9 (Folate)",
    "vitamin b12" => "Vitamin B12",
    "cobalamin" => "Vitamin B12",

    # Water
    "water" => "Water",
    "moisture" => "Water",

    # Ash/minerals
    "ash" => "Ash",
    "alcohol" => "Alcohol",
    "caffeine" => "Caffeine",
    "theobromine" => "Theobromine",

    # Omega fatty acids
    "18:2 undifferentiated" => "Linoleic Acid (Omega-6)",
    "18:2 n-6 c,c" => "Linoleic Acid (Omega-6)",
    "18:3 undifferentiated" => "Alpha-Linolenic Acid (Omega-3)",
    "18:3 n-3 c,c,c" => "Alpha-Linolenic Acid (Omega-3)",
    "20:5 n-3" => "Eicosapentaenoic Acid (EPA)",
    "22:6 n-3" => "Docosahexaenoic Acid (DHA)"
  }

  @doc """
  Normalizes a nutrient name to its canonical form.

  Divergent twin: `Mehungry.Food.NutrientManager.normalize_nutrient_name/1`
  uses a different mapping table and falls back to capitalization, while this
  one falls back to fuzzy pattern matching. Callers depend on the respective
  behavior, so they are deliberately not unified.
  """
  def normalize_nutrient_name(name) when is_binary(name) do
    normalized =
      name
      |> String.downcase()
      |> String.trim()

    # First check exact mapping
    case Map.get(@canonical_mapping, normalized) do
      nil ->
        # Try fuzzy matching
        fuzzy_normalize(normalized)

      canonical ->
        canonical
    end
  end

  def normalize_nutrient_name(_), do: "Unknown"

  defp fuzzy_normalize(name) do
    cond do
      # Omega-3 patterns
      String.contains?(name, "omega-3") or
          (String.contains?(name, "n-3") and String.contains?(name, "18:3")) ->
        "Alpha-Linolenic Acid (Omega-3)"

      # Omega-6 patterns
      String.contains?(name, "omega-6") or
          (String.contains?(name, "n-6") and String.contains?(name, "18:2")) ->
        "Linoleic Acid (Omega-6)"

      # Vitamin patterns
      String.contains?(name, "vitamin") and String.contains?(name, "b") ->
        extract_b_vitamin_name(name)

      # Mineral patterns (single letter)
      name == "na" ->
        "Sodium"

      name == "k" ->
        "Potassium"

      name == "ca" ->
        "Calcium"

      name == "fe" ->
        "Iron"

      name == "mg" ->
        "Magnesium"

      name == "p" ->
        "Phosphorus"

      name == "zn" ->
        "Zinc"

      name == "cu" ->
        "Copper"

      name == "mn" ->
        "Manganese"

      name == "se" ->
        "Selenium"

      true ->
        # Capitalize properly
        name
        |> String.split(" ")
        |> Enum.map(&String.capitalize/1)
        |> Enum.join(" ")
    end
  end

  defp extract_b_vitamin_name(name) do
    cond do
      String.contains?(name, "thiamin") -> "Vitamin B1 (Thiamin)"
      String.contains?(name, "riboflavin") -> "Vitamin B2 (Riboflavin)"
      String.contains?(name, "niacin") -> "Vitamin B3 (Niacin)"
      String.contains?(name, "pantothenic") -> "Vitamin B5 (Pantothenic Acid)"
      String.contains?(name, "b6") or String.contains?(name, "pyridoxine") -> "Vitamin B6"
      String.contains?(name, "biotin") -> "Vitamin B7 (Biotin)"
      String.contains?(name, "folate") or String.contains?(name, "folic") -> "Vitamin B9 (Folate)"
      String.contains?(name, "b12") or String.contains?(name, "cobalamin") -> "Vitamin B12"
      true -> String.capitalize(name)
    end
  end

  @doc """
  Enhanced merge function that normalizes nutrient names first
  """
  def merge_nutrients_with_normalization(list) do
    list
    |> Enum.map(&normalize_nutrient_keys/1)
    |> Enum.reduce(%{}, fn nutrients_map, acc ->
      Map.merge(acc, nutrients_map, fn _key, v1, v2 ->
        merge_nutrient(v1, v2)
      end)
    end)
  end

  defp normalize_nutrient_keys(nutrient_map) do
    Enum.reduce(nutrient_map, %{}, fn {key, value}, acc ->
      canonical_name = normalize_nutrient_name(key)
      Map.put(acc, canonical_name, value)
    end)
  end

  defp merge_nutrient(n1, n2) do
    # Ensure both have the same canonical name
    canonical_name = normalize_nutrient_name(n1["name"])

    base = %{
      "name" => canonical_name,
      "measurement_unit" => n1["measurement_unit"],
      "amount" => (n1["amount"] || 0) + (n2["amount"] || 0)
    }

    case {n1["children"], n2["children"]} do
      {nil, nil} ->
        base

      {c1, c2} ->
        children =
          (c1 || [])
          |> Enum.concat(c2 || [])
          |> merge_children()

        Map.put(base, "children", children)
    end
  end

  defp merge_children(children) do
    children
    |> Enum.group_by(&normalize_nutrient_name(&1["name"]))
    |> Enum.map(fn {canonical_name, group} ->
      Enum.reduce(group, fn child, acc ->
        %{
          "name" => canonical_name,
          "measurement_unit" => child["measurement_unit"],
          "amount" => (acc["amount"] || 0) + (child["amount"] || 0)
        }
      end)
    end)
  end

  @doc """
  Priority order for nutrients when displaying (higher priority = appears first)
  """
  def nutrient_display_priority(nutrient_name) do
    case nutrient_name do
      "Energy" -> 1
      "Total Fat" -> 2
      "Saturated Fat" -> 3
      "Monounsaturated Fat" -> 4
      "Polyunsaturated Fat" -> 5
      "Cholesterol" -> 6
      "Sodium" -> 7
      "Protein" -> 8
      "Carbohydrates" -> 9
      "Fiber" -> 10
      "Total Sugars" -> 11
      "Added Sugars" -> 12
      "Vitamin A" -> 13
      "Vitamin C" -> 14
      "Vitamin D" -> 15
      "Calcium" -> 16
      "Iron" -> 17
      "Potassium" -> 18
      "Magnesium" -> 19
      "Zinc" -> 20
      "Vitamin B12" -> 21
      _ -> 100
    end
  end

  @doc """
  Sorts nutrients by display priority, then alphabetically
  """
  def sort_nutrients_for_display(nutrients_map) do
    Enum.sort_by(nutrients_map, fn {name, _nutrient} ->
      {nutrient_display_priority(name), name}
    end)
  end

  @gram_scale %{
    "g" => 1.0,
    "gr" => 1.0,
    "gram" => 1.0,
    "grams" => 1.0,
    # "grammar" is this app's own (misspelled) name for grams in stored recipe
    # nutrient data — the most common unit there — so it must scale as grams.
    "grammar" => 1.0,
    "grammars" => 1.0,
    "mg" => 0.001,
    "milligram" => 0.001,
    "milligrams" => 0.001,
    "µg" => 1.0e-6,
    "ug" => 1.0e-6,
    "mcg" => 1.0e-6,
    "microgram" => 1.0e-6,
    "micrograms" => 1.0e-6
  }

  @doc """
  Converts a nutrient `amount` expressed in `unit` to grams so quantities
  measured in different mass units (g / mg / µg) share one comparable scale —
  e.g. before charting them together, where the raw numbers alone are
  meaningless (500 mg would otherwise dwarf 20 g).

  Returns `{:ok, grams}` for a recognized mass unit, or `:error` for anything
  without a gram equivalent (kcal, kJ, IU, …) or a missing/blank unit.
  """
  def to_grams(amount, unit) when is_number(amount) and is_binary(unit) do
    key = unit |> String.trim() |> String.downcase()

    case Map.get(@gram_scale, key) do
      nil -> :error
      scale -> {:ok, amount * scale}
    end
  end

  def to_grams(_amount, _unit), do: :error

  # Macronutrients are the energy-yielding bulk nutrients (protein, carbs, fats
  # and their subtypes, fiber, sugars). Everything else that is a nutrient —
  # vitamins and minerals — is a micronutrient. Matched on the normalized
  # display name (see `normalize_nutrient_name/1`).
  @macro_keywords ["protein", "carbohydrate", "fiber", "fibre", "sugar", "fat", "lipid"]

  @doc """
  True when `label` names a macronutrient (protein / carbohydrate / fat family /
  fiber / sugar). Used to split nutrients into the macro vs micronutrient pies,
  which must be charted separately because grams and mg/µg can't share a scale.
  """
  def macronutrient?(label) when is_binary(label) do
    downcased = String.downcase(label)
    Enum.any?(@macro_keywords, &String.contains?(downcased, &1))
  end

  def macronutrient?(_), do: false

  # The five headline macronutrients surfaced in the calendar overviews (the
  # macros pie + the daily/weekly summary badges), in display order. Buckets are
  # matched on the raw nutrient label — not the normalized name — because the
  # stored nutrients arrive under many spellings (clean "Total Fat" from recipes,
  # USDA-style "Lipids" / "Carbohydrate, By Difference" / "Fiber, Total Dietary"
  # from ingredients). `macro_bucket/1` collapses all of those into one of these
  # five, deliberately excluding fat/sugar subtypes so they aren't double-counted.
  @macro_buckets [:protein, :fat, :carbs, :sugars, :fiber]

  @doc """
  Classifies a nutrient `label` into one of the five headline macronutrient
  buckets (`:protein`, `:fat`, `:carbs`, `:sugars`, `:fiber`) or `nil`.

  Matches on the raw label so both clean canonical names and messy USDA variants
  land in the right bucket. Fat/sugar *subtypes* (Saturated/Mono/Poly Fat, fatty
  acids, Added Sugars) are intentionally left out — the umbrella nutrient already
  covers them, and counting both would inflate the totals.
  """
  def macro_bucket(label) when is_binary(label) do
    d = label |> String.downcase() |> String.replace(~r/\s+/, " ") |> String.trim()

    cond do
      d == "" -> nil
      String.contains?(d, "protein") -> :protein
      String.contains?(d, "lipid") or d == "total fat" or d == "fat" -> :fat
      String.contains?(d, "fiber") or String.contains?(d, "fibre") -> :fiber
      String.contains?(d, "sugar") and not String.contains?(d, "added") -> :sugars
      String.contains?(d, "carbohydrate") or d == "carbs" -> :carbs
      true -> nil
    end
  end

  def macro_bucket(_), do: nil

  @doc """
  Reduces a collection of `{label, nutrient_map}` pairs (or a `name => nutrient`
  map) to a single representative nutrient per macro bucket.

  When several labels fall in the same bucket (e.g. the "Carbohydrates",
  "Carbohydrate, By Difference" and "Carbohydrate, By Summation" variants) the
  one with the largest amount wins — that picks the umbrella total over a `0.0`
  placeholder or a partial subtype. Returns a `%{bucket => nutrient_map}` map.
  """
  def macro_totals(nutrients) do
    Enum.reduce(nutrients, %{}, fn {label, nutrient}, acc ->
      case macro_bucket(label) do
        nil ->
          acc

        bucket ->
          case acc do
            %{^bucket => current} ->
              if macro_amount(nutrient) > macro_amount(current),
                do: Map.put(acc, bucket, nutrient),
                else: acc

            _ ->
              Map.put(acc, bucket, nutrient)
          end
      end
    end)
  end

  @doc """
  The macro bucket atoms in display order.
  """
  def macro_buckets, do: @macro_buckets

  defp macro_amount(%{"amount" => a}) when is_number(a), do: a * 1.0
  defp macro_amount(_), do: 0.0

  @doc """
  Scales a recipe's *total* nutrition down to the amount actually consumed.

  A recipe's stored `nutrients` are the total for the whole recipe (which yields
  `recipe.servings` servings). A logged meal records how many of those servings
  were eaten (`consume_portions`), so the nutrition attributable to the meal is
  the total times `consume_portions / servings`.

  `servings` is read from the `:servings` key on the recipe_user_meal map, or the
  nested `:recipe`'s `servings` when it isn't hoisted (the `LandingLive` shape).
  Falls back to `1.0` (the raw total) when either value is missing or `servings`
  is non-positive, so callers that don't supply portions are unaffected.
  """
  def consumed_fraction(recipe_user_meal) do
    servings = recipe_servings(recipe_user_meal)
    consumed = Map.get(recipe_user_meal, :consume_portions)

    case {consumed, servings} do
      {c, s} when is_number(c) and is_number(s) and s > 0 -> c / s
      _ -> 1.0
    end
  end

  defp recipe_servings(recipe_user_meal) do
    cond do
      is_number(Map.get(recipe_user_meal, :servings)) ->
        Map.get(recipe_user_meal, :servings)

      is_map(Map.get(recipe_user_meal, :recipe)) ->
        Map.get(Map.get(recipe_user_meal, :recipe), :servings)

      true ->
        nil
    end
  end

  @doc """
  Scales every nutrient `amount` in a `name => nutrient` map (including nested
  `children`) by `factor`, preserving the rest of the map shape. Used to turn a
  recipe's stored total nutrition into the amount actually consumed.
  """
  def scale_nutrient_map(nutrients, factor) when is_map(nutrients) and is_number(factor) do
    Map.new(nutrients, fn {name, nutrient} -> {name, scale_nutrient(nutrient, factor)} end)
  end

  defp scale_nutrient(%{"children" => children} = nutrient, factor) when is_list(children) do
    nutrient
    |> scale_amount(factor)
    |> Map.put("children", Enum.map(children, &scale_nutrient(&1, factor)))
  end

  defp scale_nutrient(nutrient, factor), do: scale_amount(nutrient, factor)

  defp scale_amount(%{"amount" => amount} = nutrient, factor) when is_number(amount) do
    Map.put(nutrient, "amount", amount * factor)
  end

  defp scale_amount(nutrient, _factor), do: nutrient

  @doc """
  Your original summarize_meals_nutrients but using the enhanced merger
  """
  def summarize_meals_nutrients(user_meals) do
    result =
      user_meals
      |> Enum.flat_map(fn item ->
        recipe_nutrients =
          item
          |> Map.get(:recipe_user_meals, [])
          |> Enum.map(fn recipe_user_meal ->
            recipe_user_meal
            |> Map.get(:recipe_nutrients, %{})
            |> scale_nutrient_map(consumed_fraction(recipe_user_meal))
          end)
          |> Enum.filter(&(&1 != %{}))

        ingredient_nutrients =
          item
          |> Map.get(:ingredient_user_meals, [])
          |> Enum.flat_map(fn ing ->
            Map.get(ing, :recipe, %{})
            |> Map.get(:nutrients, [])
            |> Enum.map(fn n ->
              %{
                n.name => %{
                  "amount" => n.amount,
                  "measurement_unit" => n.measurement_unit.name,
                  "name" => n.name
                }
              }
            end)
          end)

        recipe_nutrients ++ ingredient_nutrients
      end)

    # Use enhanced merger with normalization
    merged = merge_nutrients_with_normalization(result)

    # Sort for display
    sort_nutrients_for_display(merged)
    |> Enum.into(%{})
  end
end
