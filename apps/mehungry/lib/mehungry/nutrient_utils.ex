defmodule Mehungry.NutrientUtils do
  @moduledoc """
  Handles merging of USDA nutrient data with intelligent normalization.
  De-duplicates equivalent nutrients (e.g., different energy calculation methods).
  """

  @doc """
  Master mapping of nutrient names to their canonical form
  """
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
  Normalizes a nutrient name to its canonical form
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

  @doc """
  Your original summarize_meals_nutrients but using the enhanced merger
  """
  def summarize_meals_nutrients(user_meals) do
    result =
      user_meals
      |> Enum.flat_map(fn item ->
        recipe_nutrients =
          item
          |> Map.get(:recipe_user_meals)
          |> Enum.map(&Map.get(&1, :recipe_nutrients, %{}))
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
