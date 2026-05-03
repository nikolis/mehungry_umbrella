defmodule Mehungry.Food.NutrientMerger do
  @moduledoc """
  Handles merging of USDA nutrient data with intelligent normalization.
  De-duplicates equivalent nutrients (e.g., different energy calculation methods).
  Supports both atom and string keys, and handles nested children nutrients.
  Returns all nutrients with atom keys for consistency.
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

  @doc """
  Priority order for nutrients when displaying
  """
  def nutrient_display_priority(nutrient_name) do
    case nutrient_name do
      "Energy" -> 1
      "Protein" -> 2
      "Total Fat" -> 3
      "Saturated Fat" -> 4
      "Monounsaturated Fat" -> 5
      "Polyunsaturated Fat" -> 6
      "Trans Fat" -> 7
      "Cholesterol" -> 8
      "Carbohydrates" -> 9
      "Fiber" -> 10
      "Total Sugars" -> 11
      "Added Sugars" -> 12
      "Sodium" -> 13
      "Potassium" -> 14
      "Calcium" -> 15
      "Iron" -> 16
      "Vitamins" -> 17
      "Minerals" -> 18
      _ -> 100
    end
  end

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

  def get_value(map, key) when is_atom(key), do: map[key] || map[to_string(key)]
  def get_value(map, key) when is_binary(key), do: map[key] || map[String.to_atom(key)]

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

  def find_parent_category(nutrient_name) do
    name_lower = String.downcase(nutrient_name)

    # Check for individual sugars (go under Total Sugars)
    if name_lower =~ ~r/^(glucose|fructose|sucrose|lactose|maltose|galactose)$/ do
      return("Total Sugars")
    end

    # Check for SFA patterns
    if name_lower =~ ~r/^sfa\s/i or
         name_lower =~ ~r/^sfa$/i or
         (name_lower =~ ~r/\d+:\d+/ and name_lower =~ ~r/saturated/i) or
         name_lower =~ ~r/sfa\s*\d+:\d+/i or
         name_lower =~ ~r/sfa\d+:\d+/i do
      return("Saturated Fat")
    end

    # Check for MUFA patterns
    if name_lower =~ ~r/^mufa\s/i or
         name_lower =~ ~r/^mufa$/i or
         (name_lower =~ ~r/\d+:\d+/ and name_lower =~ ~r/monounsaturated/i) or
         name_lower =~ ~r/mufa\s*\d+:\d+/i or
         name_lower =~ ~r/mufa\d+:\d+/i or
         (name_lower =~ ~r/mufa/i and name_lower =~ ~r/\d+:\d+/) do
      return("Monounsaturated Fat")
    end

    # Check for PUFA patterns
    if name_lower =~ ~r/^pufa\s/i or
         name_lower =~ ~r/^pufa$/i or
         (name_lower =~ ~r/\d+:\d+/ and name_lower =~ ~r/polyunsaturated/i) or
         name_lower =~ ~r/pufa\s*\d+:\d+/i or
         name_lower =~ ~r/pufa\d+:\d+/i or
         name_lower =~ ~r/linoleic|linolenic|arachidonic/i or
         (name_lower =~ ~r/pufa/i and name_lower =~ ~r/\d+:\d+/) do
      return("Polyunsaturated Fat")
    end

    # Check for Trans patterns
    if name_lower =~ ~r/trans/i and not name_lower =~ ~r/total/i do
      return("Trans Fat")
    end

    # Check for vitamins
    if name_lower =~
         ~r/vitamin|retinol|carotene|ascorbic|tocopherol|phylloquinone|thiamin|riboflavin|niacin|pantothenic|pyridoxine|biotin|folate|cobalamin|choline/i do
      cond do
        name_lower =~ ~r/vitamin a|retinol|carotene/i -> return("Vitamin A")
        name_lower =~ ~r/vitamin c|ascorbic/i -> return("Vitamin C")
        name_lower =~ ~r/vitamin d|cholecalciferol/i -> return("Vitamin D")
        name_lower =~ ~r/vitamin e|tocopherol/i -> return("Vitamin E")
        name_lower =~ ~r/vitamin k|phylloquinone/i -> return("Vitamin K")
        name_lower =~ ~r/thiamin|vitamin b1/i -> return("Vitamin B1")
        name_lower =~ ~r/riboflavin|vitamin b2/i -> return("Vitamin B2")
        name_lower =~ ~r/niacin|vitamin b3/i -> return("Vitamin B3")
        name_lower =~ ~r/pantothenic|vitamin b5/i -> return("Vitamin B5")
        name_lower =~ ~r/vitamin b6|pyridoxine/i -> return("Vitamin B6")
        name_lower =~ ~r/biotin|vitamin b7/i -> return("Vitamin B7")
        name_lower =~ ~r/folate|folic|vitamin b9/i -> return("Folate")
        name_lower =~ ~r/vitamin b12|cobalamin/i -> return("Vitamin B12")
        name_lower =~ ~r/choline/i -> return("Choline")
        true -> "Vitamins"
      end
    end

    # Check for minerals
    if name_lower =~
         ~r/calcium|\bca\b|iron|\bfe\b|magnesium|\bmg\b|phosphorus|\bp\b|potassium|\bk\b|sodium|\bna\b|zinc|\bzn\b|copper|\bcu\b|manganese|\bmn\b|selenium|\bse\b/i do
      cond do
        name_lower =~ ~r/calcium|\bca\b/i -> return("Calcium")
        name_lower =~ ~r/iron|\bfe\b/i -> return("Iron")
        name_lower =~ ~r/magnesium|\bmg\b/i -> return("Magnesium")
        name_lower =~ ~r/phosphorus|\bp\b/i -> return("Phosphorus")
        name_lower =~ ~r/potassium|\bk\b/i -> return("Potassium")
        name_lower =~ ~r/sodium|\bna\b/i -> return("Sodium")
        name_lower =~ ~r/zinc|\bzn\b/i -> return("Zinc")
        name_lower =~ ~r/copper|\bcu\b/i -> return("Copper")
        name_lower =~ ~r/manganese|\bmn\b/i -> return("Manganese")
        name_lower =~ ~r/selenium|\bse\b/i -> return("Selenium")
        true -> "Minerals"
      end
    end

    nil
  end

  defp return(value), do: value

  @doc """
  Normalizes units - converts mcg/mg to appropriate units
  """
  def normalize_units(
        %{"name" => name, "amount" => amount, "measurement_unit" => unit} = nutrient
      ) do
    name_lower = String.downcase(name)
    unit_lower = String.downcase(unit)

    {converted_amount, new_unit} =
      cond do
        # Energy conversions
        (name_lower == "energy" or String.contains?(name_lower, "energy")) and
            (unit_lower == "kj" or unit_lower == "kilojoule") ->
          {amount / 4.184, "kcal"}

        # Weight conversions to grams for macros
        unit_lower == "mg" or unit_lower == "milligram" ->
          {amount / 1000, "g"}

        unit_lower == "mcg" or unit_lower == "microgram" or unit_lower == "μg" ->
          {amount / 1_000_000, "g"}

        unit_lower == "grammar" or unit_lower == "gram" ->
          {amount, "g"}

        # Keep as is
        true ->
          {amount, unit}
      end

    %{
      "name" => name,
      "amount" => converted_amount,
      "measurement_unit" => new_unit
    }
  end

  def normalize_units(nutrient), do: nutrient

  def normalize_keys(nutrient) when is_list(nutrient), do: Enum.map(nutrient, &normalize_keys/1)

  def normalize_keys(%{} = nutrient) do
    result = %{
      "name" => get_value(nutrient, :name) || get_value(nutrient, "name") || "Unknown",
      "amount" => get_value(nutrient, :amount) || get_value(nutrient, "amount") || 0,
      "measurement_unit" =>
        get_value(nutrient, :measurement_unit) || get_value(nutrient, "measurement_unit") || "g"
    }

    children = get_value(nutrient, :children) || get_value(nutrient, "children")

    if children && (is_list(children) && length(children) > 0) do
      Map.put(result, "children", normalize_keys(children))
    else
      result
    end
  end

  @doc """
  Merges a list of nutrients and creates proper hierarchical structure
  """
  def merge_nutrients(nutrient_list) when is_list(nutrient_list) do
    normalized_list =
      nutrient_list
      |> Enum.map(&normalize_keys/1)
      |> Enum.map(&normalize_units/1)

    # First, group by canonical name
    grouped =
      normalized_list
      |> Enum.group_by(fn nutrient ->
        normalize_nutrient_name(nutrient["name"])
      end)
      |> Enum.map(fn {canonical_name, group} ->
        {canonical_name,
         %{
           "name" => canonical_name,
           "amount" => Enum.reduce(group, 0, fn n, acc -> acc + (n["amount"] || 0) end),
           "measurement_unit" => determine_best_unit(group, canonical_name),
           "children" => []
         }}
      end)
      |> Enum.into(%{})

    # Build hierarchical structure
    hierarchical = build_hierarchy_simple(grouped)

    hierarchical
    |> to_atom_keys()
  end

  defp determine_best_unit(group, canonical_name) do
    cond do
      canonical_name == "Energy" ->
        "kcal"

      String.contains?(canonical_name, "Vitamin") ->
        "mg"

      true ->
        group
        |> Enum.map(& &1["measurement_unit"])
        |> Enum.frequencies()
        |> Enum.max_by(fn {_unit, count} -> count end)
        |> elem(0)
    end
  end

  # Simple version of build_hierarchy to avoid pattern matching issues
  defp build_hierarchy_simple(flat_map) do
    # Initialize collections
    total_fat = Map.get(flat_map, "Total Fat")
    saturated_list = []
    monounsaturated_list = []
    polyunsaturated_list = []
    trans_list = []
    vitamin_list = []
    mineral_list = []
    sugar_list = []
    other_list = []

    # Categorize each nutrient
    {saturated_list, monounsaturated_list, polyunsaturated_list, trans_list, vitamin_list,
     mineral_list, sugar_list,
     other_list} =
      Enum.reduce(
        flat_map,
        {saturated_list, monounsaturated_list, polyunsaturated_list, trans_list, vitamin_list,
         mineral_list, sugar_list, other_list},
        fn {name, nutrient}, {sat, mono, poly, trans, vita, min, sugar, other} ->
          cond do
            # Skip Total Fat itself
            name == "Total Fat" ->
              {sat, mono, poly, trans, vita, min, sugar, other}

            # Check for SFA
            String.starts_with?(name, "Sfa") or name == "Saturated Fat" or
                (String.contains?(name, "Saturated") and name != "Total Fat") ->
              {[nutrient | sat], mono, poly, trans, vita, min, sugar, other}

            # Check for MUFA  
            String.starts_with?(name, "Mufa") or name == "Monounsaturated Fat" or
                (String.contains?(name, "Monounsaturated") and name != "Total Fat") ->
              {sat, [nutrient | mono], poly, trans, vita, min, sugar, other}

            # Check for PUFA
            String.starts_with?(name, "Pufa") or name == "Polyunsaturated Fat" or
                (String.contains?(name, "Polyunsaturated") and name != "Total Fat") ->
              {sat, mono, [nutrient | poly], trans, vita, min, sugar, other}

            # Check for Trans
            String.contains?(name, "Trans") or name == "Trans Fat" ->
              {sat, mono, poly, [nutrient | trans], vita, min, sugar, other}

            # Check for vitamins
            String.contains?(name, "Vitamin") or
              String.contains?(name, "vitamin") or
                name in ["Folate", "Choline", "Beta-Carotene", "Pantothenic Acid", "Retinol"] ->
              {sat, mono, poly, trans, [nutrient | vita], min, sugar, other}

            # Check for minerals
            name in [
              "Calcium",
              "Iron",
              "Magnesium",
              "Phosphorus",
              "Potassium",
              "Sodium",
              "Zinc",
              "Copper",
              "Manganese",
              "Selenium"
            ] or
              String.ends_with?(name, "cium") or String.ends_with?(name, "ium") ->
              {sat, mono, poly, trans, vita, [nutrient | min], sugar, other}

            # Check for sugars
            name in ["Glucose", "Fructose", "Sucrose", "Lactose", "Maltose", "Galactose"] or
                String.contains?(name, "Sugar") ->
              {sat, mono, poly, trans, vita, min, [nutrient | sugar], other}

            # Everything else
            true ->
              {sat, mono, poly, trans, vita, min, sugar, [nutrient | other]}
          end
        end
      )

    # Build result map
    result = %{}

    # Add Total Fat with its children
    result =
      if total_fat do
        children = []

        # Add Saturated Fat
        if saturated_list != [] do
          sat_total = Enum.reduce(saturated_list, 0, fn n, acc -> acc + n["amount"] end)

          children =
            children ++
              [
                %{
                  "name" => "Saturated Fat",
                  "amount" => sat_total,
                  "measurement_unit" => "g",
                  "children" => Enum.sort_by(saturated_list, & &1["name"])
                }
              ]
        end

        # Add Monounsaturated Fat
        if monounsaturated_list != [] do
          mono_total = Enum.reduce(monounsaturated_list, 0, fn n, acc -> acc + n["amount"] end)

          children =
            children ++
              [
                %{
                  "name" => "Monounsaturated Fat",
                  "amount" => mono_total,
                  "measurement_unit" => "g",
                  "children" => Enum.sort_by(monounsaturated_list, & &1["name"])
                }
              ]
        end

        # Add Polyunsaturated Fat
        if polyunsaturated_list != [] do
          poly_total = Enum.reduce(polyunsaturated_list, 0, fn n, acc -> acc + n["amount"] end)

          children =
            children ++
              [
                %{
                  "name" => "Polyunsaturated Fat",
                  "amount" => poly_total,
                  "measurement_unit" => "g",
                  "children" => Enum.sort_by(polyunsaturated_list, & &1["name"])
                }
              ]
        end

        # Add Trans Fat
        if trans_list != [] do
          trans_total = Enum.reduce(trans_list, 0, fn n, acc -> acc + n["amount"] end)

          children =
            children ++
              [
                %{
                  "name" => "Trans Fat",
                  "amount" => trans_total,
                  "measurement_unit" => "g",
                  "children" => Enum.sort_by(trans_list, & &1["name"])
                }
              ]
        end

        Map.put(result, "Total Fat", %{total_fat | "children" => children})
      else
        # If no Total Fat, add individual fat categories
        result
        |> add_if_not_empty(saturated_list, "Saturated Fat")
        |> add_if_not_empty(monounsaturated_list, "Monounsaturated Fat")
        |> add_if_not_empty(polyunsaturated_list, "Polyunsaturated Fat")
        |> add_if_not_empty(trans_list, "Trans Fat")
      end

    # Add remaining categories
    result = add_if_not_empty(result, vitamin_list, "Vitamins")
    result = add_if_not_empty(result, mineral_list, "Minerals")
    result = add_if_not_empty(result, sugar_list, "Total Sugars")

    # Add all other nutrients
    result =
      Enum.reduce(other_list, result, fn nutrient, acc ->
        Map.put(acc, nutrient["name"], nutrient)
      end)

    result
  end

  defp add_if_not_empty(result, [], _), do: result

  defp add_if_not_empty(result, list, name) when is_list(list) and list != [] do
    if Map.has_key?(result, name) do
      result
    else
      total = Enum.reduce(list, 0, fn n, acc -> acc + n["amount"] end)
      unit = List.first(list)["measurement_unit"] || "g"

      Map.put(result, name, %{
        "name" => name,
        "amount" => total,
        "measurement_unit" => unit,
        "children" => Enum.sort_by(list, & &1["name"])
      })
    end
  end

  defp determine_best_unit(group, canonical_name) do
    cond do
      canonical_name == "Energy" ->
        "kcal"

      String.contains?(canonical_name, "Vitamin") ->
        "mg"

      true ->
        group
        |> Enum.map(& &1["measurement_unit"])
        |> Enum.frequencies()
        |> Enum.max_by(fn {_unit, count} -> count end)
        |> elem(0)
    end
  end

  defp categorize_remaining(remaining, categories) do
    Enum.reduce(remaining, {categories, []}, fn {name, nutrient}, {acc, other} ->
      cond do
        # Check for SFA fatty acids
        String.starts_with?(String.downcase(name), "sfa") or
            (String.contains?(name, "Saturated") and name != "Saturated Fat") ->
          {%{acc | saturated: [nutrient | acc.saturated]}, other}

        # Check for MUFA fatty acids
        String.starts_with?(String.downcase(name), "mufa") or
            (String.contains?(name, "Monounsaturated") and name != "Monounsaturated Fat") ->
          {%{acc | monounsaturated: [nutrient | acc.monounsaturated]}, other}

        # Check for PUFA fatty acids
        String.starts_with?(String.downcase(name), "pufa") or
            (String.contains?(name, "Polyunsaturated") and name != "Polyunsaturated Fat") ->
          {%{acc | polyunsaturated: [nutrient | acc.polyunsaturated]}, other}

        # Check for Trans fatty acids
        String.contains?(name, "Trans") and name != "Trans Fat" ->
          {%{acc | trans: [nutrient | acc.trans]}, other}

        # Check for individual sugars
        name in ["Glucose", "Fructose", "Sucrose", "Lactose", "Maltose", "Galactose"] or
            (String.contains?(name, "Sugar") and not String.contains?(name, "Total")) ->
          {%{acc | individual_sugars: [nutrient | acc.individual_sugars]}, other}

        # Check for vitamins
        String.contains?(name, "Vitamin") or
          String.contains?(name, "vitamin") or
            name in [
              "Folate",
              "Choline",
              "Beta-Carotene",
              "Retinol",
              "Ascorbic Acid",
              "Pantothenic Acid"
            ] ->
          normalized = %{nutrient | "name" => normalize_nutrient_name(name)}
          {%{acc | vitamins: [normalized | acc.vitamins]}, other}

        # Check for minerals
        name in [
          "Calcium",
          "Iron",
          "Magnesium",
          "Phosphorus",
          "Potassium",
          "Sodium",
          "Zinc",
          "Copper",
          "Manganese",
          "Selenium"
        ] or
          String.contains?(name, "Calcium") or
          String.contains?(name, "Iron") or
          String.contains?(name, "Magnesium") or
          String.contains?(name, "Phosphorus") or
          String.contains?(name, "Potassium") or
          String.contains?(name, "Sodium") or
          String.contains?(name, "Zinc") or
          String.contains?(name, "Copper") or
          String.contains?(name, "Manganese") or
            String.contains?(name, "Selenium") ->
          normalized = %{nutrient | "name" => normalize_nutrient_name(name)}
          {%{acc | minerals: [normalized | acc.minerals]}, other}

        true ->
          {acc, other ++ [nutrient]}
      end
    end)
  end

  defp add_child_category(children_acc, [], _), do: children_acc

  defp add_child_category(children_acc, category_list, parent_name) do
    if category_list == [] do
      children_acc
    else
      total_amount = Enum.reduce(category_list, 0, fn n, acc -> acc + n["amount"] end)

      parent = %{
        "name" => parent_name,
        "amount" => total_amount,
        "measurement_unit" => "g",
        "children" => Enum.sort_by(category_list, & &1["name"])
      }

      children_acc ++ [parent]
    end
  end

  defp add_standalone_category(result, [], _), do: result

  defp add_standalone_category(result, category_list, parent_name) do
    if category_list == [] or Map.has_key?(result, parent_name) do
      result
    else
      total_amount = Enum.reduce(category_list, 0, fn n, acc -> acc + n["amount"] end)

      Map.put(result, parent_name, %{
        "name" => parent_name,
        "amount" => total_amount,
        "measurement_unit" => "g",
        "children" => Enum.sort_by(category_list, & &1["name"])
      })
    end
  end

  @doc """
  Merges nutrients and returns as a sorted list
  """
  def merge_nutrients_to_list(nutrient_list) do
    nutrient_list
    |> merge_nutrients()
    |> map_to_sorted_list()
  end

  def merge_flat_list(nutrient_list) do
    merge_nutrients_to_list(nutrient_list)
  end

  def map_to_sorted_list(merged_map) when is_map(merged_map) do
    merged_map
    |> Enum.sort_by(fn {name, _nutrient} ->
      {nutrient_display_priority(to_string(name)), to_string(name)}
    end)
    |> Enum.map(fn {_name, nutrient} -> nutrient end)
  end

  def summarize_meals_nutrients(user_meals) do
    all_nutrients =
      user_meals
      |> Enum.flat_map(fn item ->
        recipe_nutrients =
          item
          |> Map.get(:recipe_user_meals, [])
          |> Enum.flat_map(fn recipe_meal ->
            Map.get(recipe_meal, :recipe_nutrients, [])
          end)

        ingredient_nutrients =
          item
          |> Map.get(:ingredient_user_meals, [])
          |> Enum.flat_map(fn ing ->
            recipe = Map.get(ing, :recipe, %{})
            nutrients = Map.get(recipe, :nutrients, [])

            Enum.map(nutrients, fn n ->
              %{
                name: Map.get(n, :name) || Map.get(n, "name"),
                amount: Map.get(n, :amount) || Map.get(n, "amount") || 0,
                measurement_unit:
                  Map.get(n, :measurement_unit) ||
                    Map.get(n, "measurement_unit") ||
                    "g",
                children: Map.get(n, :children) || Map.get(n, "children") || []
              }
            end)
          end)

        recipe_nutrients ++ ingredient_nutrients
      end)

    merge_nutrients_to_list(all_nutrients)
  end
end
