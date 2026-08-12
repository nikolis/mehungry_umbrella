defmodule Mehungry.Food.NutrientMerger do
  @moduledoc """
  Shared nutrient-name and key primitives.

  This module used to carry a second, divergent recipe-nutrient hierarchy
  builder (`merge_nutrients/1`, `build_hierarchy_simple/1`, `normalize_units/1`,
  …) that duplicated `Mehungry.Food.NutrientHierarchyBuilder`, silently dropped
  fat subcategories, and had no production callers. It was removed. What remains
  are the genuinely shared primitives:

    * `normalize_nutrient_name/1` — name → canonical form (capitalizes unknowns)
    * `to_string_keys/1` / `to_atom_keys/1` — deep key coercion for stored maps

  The per-day/-week/-meal meal summariser lives in
  `Mehungry.NutrientUtils.summarize_meals_nutrients/1` — that is the single
  canonical implementation. Don't reintroduce a second summariser or hierarchy
  builder here.
  """

  # Master mapping of nutrient names to their canonical form
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

    # Fat subcategories
    "fatty acids, total saturated" => "Saturated Fat",
    "fatty acids, total monounsaturated" => "Monounsaturated Fat",
    "fatty acids, total polyunsaturated" => "Polyunsaturated Fat",
    "total saturated fatty acids" => "Saturated Fat",
    "total monounsaturated fatty acids" => "Monounsaturated Fat",
    "total polyunsaturated fatty acids" => "Polyunsaturated Fat",
    "saturated fat" => "Saturated Fat",
    "monounsaturated fat" => "Monounsaturated Fat",
    "polyunsaturated fat" => "Polyunsaturated Fat",
    "sfa" => "Saturated Fat",
    "mufa" => "Monounsaturated Fat",
    "pufa" => "Polyunsaturated Fat",

    # Trans fat
    "fatty acids, total trans" => "Trans Fat",
    "fatty acids, total trans-monoenoic" => "Trans Fat",
    "fatty acids, total trans-polyenoic" => "Trans Fat",
    "trans fat" => "Trans Fat",
    "tfa" => "Trans Fat",

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
    "sugars, total including nlea" => "Total Sugars",
    "sugar" => "Total Sugars",
    "added sugars" => "Added Sugars",
    "glucose" => "Glucose",
    "fructose" => "Fructose",
    "sucrose" => "Sucrose",
    "lactose" => "Lactose",
    "maltose" => "Maltose",
    "galactose" => "Galactose",

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
    "vitamin a (rae)" => "Vitamin A",
    "carotene, beta" => "Beta-Carotene",
    "beta-carotene" => "Beta-Carotene",
    "vitamin c" => "Vitamin C",
    "ascorbic acid" => "Vitamin C",
    "vitamin d" => "Vitamin D",
    "vitamin d (d2 + d3)" => "Vitamin D",
    "vitamin e" => "Vitamin E",
    "alpha-tocopherol" => "Vitamin E",
    "vitamin k" => "Vitamin K",
    "phylloquinone" => "Vitamin K",
    "vitamin b12" => "Vitamin B12",
    "cobalamin" => "Vitamin B12",
    "choline, total" => "Choline",
    "choline" => "Choline",
    "thiamin" => "Vitamin B1",
    "riboflavin" => "Vitamin B2",
    "niacin" => "Vitamin B3",
    "vitamin b6" => "Vitamin B6",
    "pantothenic acid" => "Vitamin B5",
    "folate" => "Folate",
    "folic acid" => "Folate",
    "biotin" => "Vitamin B7",

    # Other
    "ash" => "Ash",
    "water" => "Water",
    "alcohol" => "Alcohol",
    "caffeine" => "Caffeine"
  }

  # Divergent twin: `Mehungry.NutrientUtils.normalize_nutrient_name/1` uses a
  # different mapping table and a fuzzy-match fallback; this one falls back to
  # capitalization. Deliberately not unified — callers rely on each behavior.
  def normalize_nutrient_name(nil), do: "Unknown"

  def normalize_nutrient_name(name) when is_atom(name),
    do: normalize_nutrient_name(to_string(name))

  def normalize_nutrient_name(name) when is_binary(name) do
    normalized = name |> String.downcase() |> String.trim()
    Map.get(@canonical_mapping, normalized, capitalize_name(name))
  end

  defp capitalize_name(name) do
    name
    |> String.split(" ")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  def to_string_keys(nil), do: nil
  def to_string_keys(list) when is_list(list), do: Enum.map(list, &to_string_keys/1)

  def to_string_keys(%{} = map) do
    Enum.reduce(map, %{}, fn {k, v}, acc -> Map.put(acc, to_string(k), to_string_keys(v)) end)
  end

  def to_string_keys(other), do: other

  def to_atom_keys(nil), do: nil
  def to_atom_keys(list) when is_list(list), do: Enum.map(list, &to_atom_keys/1)

  def to_atom_keys(%{} = map) do
    Enum.reduce(map, %{}, fn {k, v}, acc ->
      key =
        case to_string(k) do
          "children" -> :children
          other -> String.to_atom(other)
        end

      Map.put(acc, key, to_atom_keys(v))
    end)
  end

  def to_atom_keys(other), do: other
end
