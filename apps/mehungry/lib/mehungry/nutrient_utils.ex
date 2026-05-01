defmodule Mehungry.Food.NutrientUtils do

  @moduledoc """
  Handles merging of USDA nutrient data with intelligent normalization.
  De-duplicates equivalent nutrients (e.g., different energy calculation methods).
  Supports both atom and string keys, and handles nested children nutrients.
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
    "energy (kj)" => "Energy",
    "energy (kilojoule)" => "Energy",
    "kilojoule" => "Energy",
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
    "carbohydrate, by difference" => "Carbohydrates",
    "total carbohydrate" => "Carbohydrates",
    "carbs" => "Carbohydrates",

    # Fiber variations
    "fiber" => "Fiber",
    "total dietary fiber" => "Fiber",
    "fiber, total dietary" => "Fiber",
    "dietary fiber" => "Fiber",
    "crude fiber" => "Fiber",

    # Sugar variations
    "sugars" => "Total Sugars",
    "total sugars" => "Total Sugars",
    "sugar" => "Total Sugars",
    "added sugars" => "Added Sugars",

    # Saturated Fat variations
    "saturated fat" => "Saturated Fat",
    "fatty acids, total saturated" => "Saturated Fat",
    "total saturated fatty acids" => "Saturated Fat",
    "sfa" => "Saturated Fat",

    # Monounsaturated Fat variations
    "monounsaturated fat" => "Monounsaturated Fat",
    "fatty acids, total monounsaturated" => "Monounsaturated Fat",
    "total monounsaturated fatty acids" => "Monounsaturated Fat",
    "monounsaturated fatty acids" => "Monounsaturated Fat",
    "mufa" => "Monounsaturated Fat",

    # Polyunsaturated Fat variations
    "polyunsaturated fat" => "Polyunsaturated Fat",
    "fatty acids, total polyunsaturated" => "Polyunsaturated Fat",
    "total polyunsaturated fatty acids" => "Polyunsaturated Fat",
    "polyunsaturated fatty acids" => "Polyunsaturated Fat",
    "pufa" => "Polyunsaturated Fat",

    # Cholesterol
    "cholesterol" => "Cholesterol",
    "total cholesterol" => "Cholesterol",

    # Minerals
    "sodium" => "Sodium",
    "na" => "Sodium",
    "potassium" => "Potassium",
    "k" => "Potassium",
    "calcium, ca" => "Calcium",
    "calcium" => "Calcium",
    "ca" => "Calcium",
    "iron" => "Iron",
    "fe" => "Iron",
    "magnesium" => "Magnesium",
    "mg" => "Magnesium",
    "phosphorus" => "Phosphorus",
    "p" => "Phosphorus",
    "zinc" => "Zinc",
    "zn" => "Zinc",
    "copper, cu" => "Copper",
    "copper" => "Copper",
    "cu" => "Copper",
    "manganese" => "Manganese",
    "mn" => "Manganese",
    "selenium" => "Selenium",
    "se" => "Selenium",

    # Vitamins
    "vitamin a" => "Vitamin A",
    "carotene, beta" => "Vitamin A (Beta-Carotene)",
    "beta-carotene" => "Vitamin A (Beta-Carotene)",
    "vitamin c" => "Vitamin C",
    "ascorbic acid" => "Vitamin C",
    "vitamin d" => "Vitamin D",
    "vitamin e" => "Vitamin E",
    "vitamin k" => "Vitamin K",
    "vitamin b12" => "Vitamin B12",
    "cobalamin" => "Vitamin B12",
    "choline, total" => "Choline",
    "choline" => "Choline",

    # Amino Acids
    "alanine" => "Alanine",
    "arginine" => "Arginine",
    "aspartic acid" => "Aspartic Acid",
    "cystine" => "Cystine",
    "glutamic acid" => "Glutamic Acid",
    "glycine" => "Glycine",
    "histidine" => "Histidine",
    "isoleucine" => "Isoleucine",
    "leucine" => "Leucine",
    "lysine" => "Lysine",
    "methionine" => "Methionine",
    "phenylalanine" => "Phenylalanine",
    "proline" => "Proline",
    "serine" => "Serine",
    "threonine" => "Threonine",
    "tryptophan" => "Tryptophan",
    "tyrosine" => "Tyrosine",
    "valine" => "Valine",

    # Other
    "ash" => "Ash",
    "water" => "Water",
    "alcohol" => "Alcohol",
    "caffeine" => "Caffeine",
  }

  @doc """
  Priority order for nutrients when displaying (higher priority = appears first)
  """
  def nutrient_display_priority(nutrient_name) do
    case nutrient_name do
      "Energy" -> 1
      "Protein" -> 2
      "Total Fat" -> 3
      "Saturated Fat" -> 4
      "Monounsaturated Fat" -> 5
      "Polyunsaturated Fat" -> 6
      "Cholesterol" -> 7
      "Carbohydrates" -> 8
      "Fiber" -> 9
      "Total Sugars" -> 10
      "Sodium" -> 11
      "Potassium" -> 12
      "Calcium" -> 13
      "Iron" -> 14
      "Vitamin A" -> 15
      "Vitamin C" -> 16
      "Vitamin D" -> 17
      "Vitamin B12" -> 18
      "Choline" -> 19
      "Ash" -> 20
      "Water" -> 21
      _ -> 100
    end
  end

  @doc """
  Normalizes a nutrient name to its canonical form
  """
  def normalize_nutrient_name(nil), do: "Unknown"

  def normalize_nutrient_name(name) when is_atom(name) do
    normalize_nutrient_name(to_string(name))
  end

  def normalize_nutrient_name(name) when is_binary(name) do
    normalized = name
    |> String.downcase()
    |> String.trim()

    # First check exact mapping
    case Map.get(@canonical_mapping, normalized) do
      nil ->
        # Try to capitalize properly
        name
        |> String.split(" ")
        |> Enum.map(&String.capitalize/1)
        |> Enum.join(" ")
      canonical -> canonical
    end
  end

  @doc """
  Safely gets a value from a map that might have atom or string keys
  """
  def get_value(map, key) when is_atom(key) do
    map[key] || map[to_string(key)]
  end
  def get_value(map, key) when is_binary(key) do
    map[key] || map[String.to_atom(key)]
  end

  @doc """
  Converts any map to have string keys recursively
  """
  def to_string_keys(nil), do: nil
  def to_string_keys(list) when is_list(list) do
    Enum.map(list, &to_string_keys/1)
  end
  def to_string_keys(%{} = map) do
    Enum.reduce(map, %{}, fn {k, v}, acc ->
      Map.put(acc, to_string(k), to_string_keys(v))
    end)
  end
  def to_string_keys(other), do: other

  @doc """
  Normalizes units to a standard format for merging
  """
  def normalize_units(%{"name" => name, "amount" => amount, "measurement_unit" => unit} = nutrient) do
    name_lower = String.downcase(name)
    unit_lower = String.downcase(unit)

    {converted_amount, new_unit} = cond do
      # Energy conversions (convert everything to kcal)
      (name_lower == "energy" or String.contains?(name_lower, "energy")) and
      (unit_lower == "kj" or unit_lower == "kilojoule") ->
        {amount / 4.184, "kcal"}

      # Weight conversions (convert everything to grams for consistency)
      unit_lower == "mg" or unit_lower == "milligram" ->
        {amount / 1000, "g"}
      unit_lower == "mcg" or unit_lower == "microgram" or unit_lower == "μg" ->
        {amount / 1_000_000, "g"}
      unit_lower == "grammar" or unit_lower == "gram" ->  # Fix typo in your data
        {amount, "g"}

      # Keep as is
      true ->
        {amount, unit}
    end

    %{
      "name" => name,
      "amount" => converted_amount,
      "measurement_unit" => new_unit,
      "original_unit" => unit
    }
  end
  def normalize_units(nutrient), do: nutrient

  @doc """
  Converts a nutrient map with atom keys to have string keys
  """
  def normalize_keys(nutrient) when is_list(nutrient) do
    Enum.map(nutrient, &normalize_keys/1)
  end

  def normalize_keys(%{} = nutrient) do
    result = %{
      "name" => get_value(nutrient, :name) || get_value(nutrient, "name") || "Unknown",
      "amount" => (get_value(nutrient, :amount) || get_value(nutrient, "amount") || 0),
      "measurement_unit" => get_value(nutrient, :measurement_unit) || get_value(nutrient, "measurement_unit") || "g"
    }

    # Handle children recursively
    children = get_value(nutrient, :children) || get_value(nutrient, "children")
    if children && (is_list(children) && length(children) > 0) do
      Map.put(result, "children", normalize_keys(children))
    else
      result
    end
  end

  @doc """
  Merges a list of nutrients (format: list of maps with name, amount, measurement_unit)
  """
  def merge_nutrients(nutrient_list) when is_list(nutrient_list) do
    # First normalize all keys to strings and convert units where possible
    normalized_list = nutrient_list
    |> Enum.map(&normalize_keys/1)
    |> Enum.map(&normalize_units/1)

    # Group by canonical name
    normalized_list
    |> Enum.group_by(fn nutrient ->
      normalize_nutrient_name(nutrient["name"])
    end)
    |> Enum.map(fn {canonical_name, group} ->
      # Merge all nutrients with the same canonical name
      merged = Enum.reduce(group, %{}, fn nutrient, acc ->
        current_amount = Map.get(acc, "amount") || 0
        current_children = Map.get(acc, "children") || []
        new_children = Map.get(nutrient, "children") || []

        %{
          "name" => canonical_name,
          "amount" => current_amount + (nutrient["amount"] || 0),
          "measurement_unit" => determine_best_unit(group, canonical_name),
          "children" => merge_children(current_children, new_children)
        }
      end)

      {canonical_name, merged}
    end)
    |> Enum.into(%{})
  end

  defp determine_best_unit(group, canonical_name) do
    # For energy, always show kcal
    if canonical_name == "Energy" do
      "kcal"
    else
      # Otherwise use the most frequent unit in the group
      group
      |> Enum.map(& &1["measurement_unit"])
      |> Enum.frequencies()
      |> Enum.max_by(fn {_unit, count} -> count end)
      |> elem(0)
    end
  end

  defp merge_children(existing_children, new_children) when is_list(existing_children) and is_list(new_children) do
    all_children = existing_children ++ new_children

    if Enum.empty?(all_children) do
      nil
    else
      all_children
      |> Enum.group_by(fn child ->
        normalize_nutrient_name(child["name"])
      end)
      |> Enum.map(fn {name, group} ->
        %{
          "name" => name,
          "amount" => Enum.reduce(group, 0, fn child, acc ->
            acc + (child["amount"] || 0)
          end),
          "measurement_unit" => List.first(group)["measurement_unit"] || "g"
        }
      end)
    end
  end

  @doc """
  Converts a merged map to a sorted list based on display priority
  """
  def map_to_sorted_list(merged_map) when is_map(merged_map) do
    merged_map
    |> Enum.sort_by(fn {name, _nutrient} ->
      {nutrient_display_priority(name), name}
    end)
    |> Enum.map(fn {_name, nutrient} -> nutrient end)
  end

  @doc """
  Merges nutrients and returns as a sorted list (useful for display)
  """
  def merge_nutrients_to_list(nutrient_list) do
    nutrient_list
    |> merge_nutrients()
    |> map_to_sorted_list()
  end

  @doc """
  Simple function to merge a flat list of nutrients directly
  """
  def merge_flat_list(nutrient_list) do
    merge_nutrients_to_list(nutrient_list)
  end

  @doc """
  Main function to summarize meals nutrients from user meals
  """
  def summarize_meals_nutrients(user_meals) do
    all_nutrients =
      user_meals
      |> Enum.flat_map(fn item ->
        # Get recipe nutrients
        recipe_nutrients =
          item
          |> Map.get(:recipe_user_meals, [])
          |> Enum.flat_map(fn recipe_meal ->
            Map.get(recipe_meal, :recipe_nutrients, [])
          end)

        # Get ingredient nutrients
        ingredient_nutrients =
          item
          |> Map.get(:ingredient_user_meals, [])
          |> Enum.flat_map(fn ing ->
            recipe = Map.get(ing, :recipe, %{})
            nutrients = Map.get(recipe, :nutrients, [])

            Enum.map(nutrients, fn n ->
              %{
                "name" => Map.get(n, :name) || Map.get(n, "name"),
                "amount" => Map.get(n, :amount) || Map.get(n, "amount") || 0,
                "measurement_unit" => Map.get(n, :measurement_unit) ||
                                      Map.get(n, "measurement_unit") ||
                                      "g",
                "children" => Map.get(n, :children) || Map.get(n, "children") || []
              }
            end)
          end)

        recipe_nutrients ++ ingredient_nutrients
      end)

    # Merge all nutrients and return as sorted list
    merge_nutrients_to_list(all_nutrients)
  end
end
