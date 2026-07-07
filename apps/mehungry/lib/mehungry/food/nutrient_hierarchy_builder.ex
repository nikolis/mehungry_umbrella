defmodule Mehungry.Food.NutrientHierarchyBuilder do
  require Logger

  @moduledoc """
  Builds hierarchical structure for nutrients with proper nesting.

  Every parent node carries two amount fields:
    - amount:        official USDA value when available, otherwise equals children_sum
    - children_sum:  sum of direct children amounts (always computed)

  When amount != children_sum the UI can display both, e.g.:
    "Carbohydrates  169g (sum) / 77g (by difference)"

  Fat hierarchy:
    Total Fat -> Fat Type (Saturated/Mono/Poly/Trans) -> Individual Fatty Acids

  Carbohydrate hierarchy:
    Total Carbohydrates
      -> Complex Carbohydrates (Fiber -> Soluble/Insoluble, Starch, Glycogen)
      -> Total Sugars (USDA entry)
           -> Monosaccharides -> [Glucose, Fructose, Galactose]
           -> Disaccharides   -> [Sucrose, Lactose, Maltose]
      -> Sugar Alcohols
      [Added Sugars as flat informational entry]
  """

  @complex_carb_names ["Starch", "Glycogen"]
  @fiber_parent_names ["Fiber", "Dietary Fiber", "Fiber, total dietary"]
  @monosaccharide_names ["Glucose", "Fructose", "Galactose"]
  @disaccharide_names ["Sucrose", "Lactose", "Maltose"]
  @sugar_alcohol_names [
    "Sugar Alcohols",
    "Sorbitol",
    "Mannitol",
    "Xylitol",
    "Erythritol",
    "Lactitol",
    "Maltitol",
    "Isomalt"
  ]
  @total_sugar_names ["Total Sugars", "Sugars, total including NLEA", "Sugars, Total"]
  @added_sugar_names ["Added Sugars", "Sugars, added"]

  def build_hierarchy(nutrients) do
    initial_state = %{
      main: %{},
      saturated_fats: [],
      monounsaturated_fats: [],
      polyunsaturated_fats: [],
      trans_fats: [],
      complex_carbs: [],
      monosaccharides: [],
      disaccharides: [],
      sugar_alcohols: [],
      total_sugars: [],
      added_sugars: [],
      vitamins: [],
      minerals: [],
      other: []
    }

    categorized =
      Enum.reduce(nutrients, initial_state, fn nutrient, acc ->
        name = nutrient.name
        name_lower = String.downcase(name)

        cond do
          name in ["Energy", "Protein", "Cholesterol"] ->
            %{acc | main: Map.put(acc.main, name, nutrient)}

          name == "Total Fat" ->
            %{acc | main: Map.put(acc.main, "Total Fat", nutrient)}

          name in ["Carbohydrates", "Total Carbohydrates", "Carbohydrate, by difference"] ->
            %{acc | main: Map.put(acc.main, "Carbohydrates", nutrient)}

          name == "Saturated Fat" or name == "Fatty Acids, Total Saturated" ->
            %{acc | saturated_fats: [nutrient | acc.saturated_fats]}

          name == "Monounsaturated Fat" or name == "Fatty Acids, Total Monounsaturated" ->
            %{acc | monounsaturated_fats: [nutrient | acc.monounsaturated_fats]}

          name == "Polyunsaturated Fat" or name == "Fatty Acids, Total Polyunsaturated" ->
            %{acc | polyunsaturated_fats: [nutrient | acc.polyunsaturated_fats]}

          name == "Trans Fat" or
            name == "Fatty Acids, Total Trans" or
            name == "Fatty Acids, Total Trans-monoenoic" or
              name == "Fatty Acids, Total Trans-polyenoic" ->
            %{acc | trans_fats: [nutrient | acc.trans_fats]}

          String.starts_with?(name_lower, "sfa") ->
            %{acc | saturated_fats: [nutrient | acc.saturated_fats]}

          String.starts_with?(name_lower, "mufa") ->
            %{acc | monounsaturated_fats: [nutrient | acc.monounsaturated_fats]}

          String.starts_with?(name_lower, "pufa") ->
            %{acc | polyunsaturated_fats: [nutrient | acc.polyunsaturated_fats]}

          String.starts_with?(name_lower, "tfa") ->
            %{acc | trans_fats: [nutrient | acc.trans_fats]}

          name in @complex_carb_names or name in @fiber_parent_names or
              String.starts_with?(name_lower, "fiber,") ->
            %{acc | complex_carbs: [nutrient | acc.complex_carbs]}

          name in @monosaccharide_names ->
            %{acc | monosaccharides: [nutrient | acc.monosaccharides]}

          name in @disaccharide_names ->
            %{acc | disaccharides: [nutrient | acc.disaccharides]}

          name in @sugar_alcohol_names ->
            %{acc | sugar_alcohols: [nutrient | acc.sugar_alcohols]}

          name in @total_sugar_names ->
            %{acc | total_sugars: [nutrient | acc.total_sugars]}

          name in @added_sugar_names ->
            %{acc | added_sugars: [nutrient | acc.added_sugars]}

          String.contains?(name_lower, "vitamin") or
              name in [
                "Folate",
                "Choline",
                "Niacin",
                "Riboflavin",
                "Thiamin",
                "Pantothenic Acid",
                "Carotene, Alpha",
                "Carotene, Beta",
                "Retinol"
              ] ->
            %{acc | vitamins: [nutrient | acc.vitamins]}

          String.contains?(name_lower, "calcium") or
            String.contains?(name_lower, "iron") or
            String.contains?(name_lower, "magnesium") or
            String.contains?(name_lower, "phosphorus") or
            String.contains?(name_lower, "potassium") or
            String.contains?(name_lower, "sodium") or
            String.contains?(name_lower, "zinc") or
            String.contains?(name_lower, "copper") or
            String.contains?(name_lower, "manganese") or
              String.contains?(name_lower, "selenium") ->
            %{acc | minerals: [nutrient | acc.minerals]}

          true ->
            %{acc | other: [nutrient | acc.other]}
        end
      end)

    build_result(categorized)
  end

  defp build_result(categorized) do
    result = %{}

    total_fat = build_total_fat(categorized)

    result =
      if not is_nil(total_fat),
        do: Map.put(result, :total_fat, total_fat),
        else: result

    total_carbs = build_total_carbohydrates(categorized)

    result =
      if not is_nil(total_carbs),
        do: Map.put(result, :total_carbohydrates, total_carbs),
        else: result

    result =
      Enum.reduce(categorized.main, result, fn {key, nutrient}, acc ->
        if key not in ["Total Fat", "Carbohydrates"],
          do: Map.put(acc, String.to_atom(key), convert_to_atom_keys(nutrient)),
          else: acc
      end)

    result =
      if categorized.vitamins != [] do
        children_sum = sum_amounts(categorized.vitamins)

        Map.put(result, :vitamins, %{
          name: "Vitamins",
          amount: children_sum,
          children_sum: children_sum,
          measurement_unit: "mg",
          children: convert_to_atom_keys(Enum.sort_by(categorized.vitamins, & &1.name))
        })
      else
        result
      end

    result =
      if categorized.minerals != [] do
        children_sum = sum_amounts(categorized.minerals)

        Map.put(result, :minerals, %{
          name: "Minerals",
          amount: children_sum,
          children_sum: children_sum,
          measurement_unit: "mg",
          children: convert_to_atom_keys(Enum.sort_by(categorized.minerals, & &1.name))
        })
      else
        result
      end

    result =
      Enum.reduce(categorized.other, result, fn nutrient, acc ->
        Map.put(acc, String.to_atom(nutrient.name), convert_to_atom_keys(nutrient))
      end)

    convert_to_atom_keys(result)
  end

  # ---------------------------------------------------------------------------
  # Fat hierarchy
  # ---------------------------------------------------------------------------

  defp build_total_fat(categorized) do
    fat_subcategories = []

    {_s, fat_subcategories} =
      build_fat_subcategory(categorized.saturated_fats, "Saturated Fat", fat_subcategories)

    {_m, fat_subcategories} =
      build_fat_subcategory(
        categorized.monounsaturated_fats,
        "Monounsaturated Fat",
        fat_subcategories
      )

    {_p, fat_subcategories} =
      build_fat_subcategory(
        categorized.polyunsaturated_fats,
        "Polyunsaturated Fat",
        fat_subcategories
      )

    {_t, fat_subcategories} =
      build_fat_subcategory(categorized.trans_fats, "Trans Fat", fat_subcategories)

    total_fat_parent = Map.get(categorized.main, "Total Fat")

    if fat_subcategories != [] do
      Logger.debug("NutrientHierarchyBuilder.build_total_fat subcategory breakdown:")

      Enum.each(fat_subcategories, fn s ->
        Logger.debug(
          "  [fat subcategory] #{s.name}: amount=#{s.amount} children_sum=#{s.children_sum}"
        )
      end)

      children_sum = sum_amounts(fat_subcategories)

      {amount, children_sum} =
        resolve_amounts("Total Fat", total_fat_parent && total_fat_parent.amount, children_sum)

      Logger.debug(
        "  => Total Fat: official=#{total_fat_parent && total_fat_parent.amount} children_sum=#{children_sum}"
      )

      unit = if total_fat_parent, do: total_fat_parent.measurement_unit, else: "g"
      name = if total_fat_parent, do: total_fat_parent.name, else: "Total Fat"

      %{
        name: name,
        amount: amount,
        children_sum: children_sum,
        measurement_unit: unit,
        children: convert_to_atom_keys(Enum.sort_by(fat_subcategories, & &1.name))
      }
    else
      nil
    end
  end

  defp build_fat_subcategory(nutrients, category_name, current_children) do
    parent = Enum.find(nutrients, fn n -> n.name == category_name end)

    individual_fatty_acids =
      Enum.filter(nutrients, fn n ->
        n.name != category_name and
          not String.contains?(n.name, "Fatty Acids, Total") and
          n.name not in [
            "Saturated Fat",
            "Monounsaturated Fat",
            "Polyunsaturated Fat",
            "Trans Fat"
          ]
      end)

    extra_totals =
      Enum.filter(nutrients, fn n ->
        String.contains?(n.name, "Fatty Acids, Total") and
          n.name not in [
            "Fatty Acids, Total Saturated",
            "Fatty Acids, Total Monounsaturated",
            "Fatty Acids, Total Polyunsaturated",
            "Fatty Acids, Total Trans",
            "Fatty Acids, Total Trans-monoenoic",
            "Fatty Acids, Total Trans-polyenoic"
          ]
      end)

    all_children = deduplicate_fatty_acids(individual_fatty_acids ++ extra_totals)

    if parent != nil or all_children != [] do
      Logger.debug("  NutrientHierarchyBuilder.build_fat_subcategory [#{category_name}]:")
      Logger.debug("    parent: #{parent && parent.name}: #{parent && parent.amount}")

      Enum.each(all_children, fn n ->
        Logger.debug("    [child] #{n.name}: #{n.amount} #{n.measurement_unit}")
      end)

      enhanced_children =
        Enum.map(all_children, fn fa ->
          %{
            name: get_fatty_acid_display_name(fa.name),
            amount: fa.amount,
            measurement_unit: fa.measurement_unit,
            original_name: fa.name
          }
        end)

      children_sum = sum_amounts(all_children)

      {amount, children_sum} =
        resolve_amounts(category_name, parent && parent.amount, children_sum)

      Logger.debug("    => amount=#{amount} children_sum=#{children_sum}")

      unit = if parent, do: parent.measurement_unit, else: "g"

      subcategory = %{
        name: category_name,
        amount: amount,
        children_sum: children_sum,
        measurement_unit: unit,
        children: convert_to_atom_keys(Enum.sort_by(enhanced_children, & &1.name))
      }

      {subcategory, [subcategory | current_children]}
    else
      {nil, current_children}
    end
  end

  defp get_fatty_acid_display_name(name) do
    name_lower = String.downcase(name)

    cond do
      String.contains?(name_lower, "22:6") or String.contains?(name_lower, "dha") ->
        "DHA (Docosahexaenoic Acid, Omega-3)"

      String.contains?(name_lower, "20:5") or String.contains?(name_lower, "epa") ->
        "EPA (Eicosapentaenoic Acid, Omega-3)"

      String.contains?(name_lower, "18:3") and String.contains?(name_lower, "n-3") ->
        "ALA (Alpha-Linolenic Acid, Omega-3)"

      String.contains?(name_lower, "18:2") and String.contains?(name_lower, "n-6") ->
        "Linoleic Acid (Omega-6)"

      String.contains?(name_lower, "20:4") and String.contains?(name_lower, "n-6") ->
        "Arachidonic Acid (Omega-6)"

      String.contains?(name_lower, "16:0") and String.contains?(name_lower, "sfa") ->
        "Palmitic Acid (C16:0)"

      String.contains?(name_lower, "18:0") and String.contains?(name_lower, "sfa") ->
        "Stearic Acid (C18:0)"

      String.contains?(name_lower, "18:1") and String.contains?(name_lower, "mufa") ->
        "Oleic Acid (Omega-9)"

      true ->
        name |> String.split(" ") |> Enum.map(&String.capitalize/1) |> Enum.join(" ")
    end
  end

  # ---------------------------------------------------------------------------
  # Carbohydrate hierarchy
  # ---------------------------------------------------------------------------

  defp build_total_carbohydrates(categorized) do
    carb_subcategories = []

    {_complex, carb_subcategories} =
      build_complex_carbs(categorized.complex_carbs, carb_subcategories)

    {_sugars, carb_subcategories} =
      build_total_sugars(
        categorized.total_sugars,
        categorized.monosaccharides,
        categorized.disaccharides,
        carb_subcategories
      )

    {_alcohols, carb_subcategories} =
      build_sugar_alcohols(categorized.sugar_alcohols, carb_subcategories)

    total_carb_parent = Map.get(categorized.main, "Carbohydrates")
    added_sugar_entries = convert_to_atom_keys(categorized.added_sugars)

    cond do
      carb_subcategories != [] ->
        sorted_children = Enum.sort_by(carb_subcategories, & &1.name) ++ added_sugar_entries
        children_sum = sum_amounts(carb_subcategories)

        {amount, children_sum} =
          resolve_amounts(
            "Carbohydrates",
            total_carb_parent && total_carb_parent.amount,
            children_sum
          )

        unit = if total_carb_parent, do: total_carb_parent.measurement_unit, else: "g"
        name = if total_carb_parent, do: total_carb_parent.name, else: "Carbohydrates"

        %{
          name: name,
          amount: amount,
          children_sum: children_sum,
          measurement_unit: unit,
          children: convert_to_atom_keys(sorted_children)
        }

      not is_nil(total_carb_parent) ->
        convert_to_atom_keys(total_carb_parent)

      true ->
        nil
    end
  end

  defp build_complex_carbs(nutrients, current_children) do
    fiber_parents = Enum.filter(nutrients, fn n -> n.name in @fiber_parent_names end)

    fiber_children =
      Enum.filter(nutrients, fn n ->
        n.name not in @fiber_parent_names and n.name not in @complex_carb_names
      end)

    plain_complex = Enum.filter(nutrients, fn n -> n.name in @complex_carb_names end)

    Logger.debug("NutrientHierarchyBuilder.build_complex_carbs breakdown:")

    Enum.each(fiber_parents, fn n ->
      Logger.debug("  [fiber parent] #{n.name}: #{n.amount} #{n.measurement_unit}")
    end)

    Enum.each(fiber_children, fn n ->
      Logger.debug("  [fiber child]  #{n.name}: #{n.amount} #{n.measurement_unit}")
    end)

    Enum.each(plain_complex, fn n ->
      Logger.debug("  [complex]      #{n.name}: #{n.amount} #{n.measurement_unit}")
    end)

    fiber_node =
      if fiber_parents != [] or fiber_children != [] do
        parent = List.first(fiber_parents)
        children_sum = sum_amounts(fiber_children)

        {amount, children_sum} =
          resolve_amounts("Dietary Fiber", parent && parent.amount, children_sum)

        unit = if parent, do: parent.measurement_unit, else: "g"

        Logger.debug("  => Dietary Fiber: amount=#{amount} children_sum=#{children_sum}")

        %{
          name: "Dietary Fiber",
          amount: amount,
          children_sum: children_sum,
          measurement_unit: unit,
          children: convert_to_atom_keys(Enum.sort_by(fiber_children, & &1.name))
        }
      end

    all_children =
      plain_complex
      |> Enum.map(&convert_to_atom_keys/1)
      |> then(fn list -> if fiber_node, do: [fiber_node | list], else: list end)
      |> Enum.sort_by(& &1.name)

    if all_children != [] do
      children_sum = sum_amounts(all_children)

      Logger.debug("  => Complex Carbohydrates total children_sum=#{children_sum}")

      subcategory = %{
        name: "Complex Carbohydrates",
        amount: children_sum,
        children_sum: children_sum,
        measurement_unit: "g",
        children: all_children
      }

      {subcategory, [subcategory | current_children]}
    else
      {nil, current_children}
    end
  end

  defp build_total_sugars(total_sugars, monosaccharides, disaccharides, current_children) do
    mono_node =
      if monosaccharides != [] do
        mono_sum = sum_amounts(monosaccharides)

        %{
          name: "Monosaccharides",
          amount: mono_sum,
          children_sum: mono_sum,
          measurement_unit: "g",
          children: convert_to_atom_keys(Enum.sort_by(monosaccharides, & &1.name))
        }
      end

    di_node =
      if disaccharides != [] do
        di_sum = sum_amounts(disaccharides)

        %{
          name: "Disaccharides",
          amount: di_sum,
          children_sum: di_sum,
          measurement_unit: "g",
          children: convert_to_atom_keys(Enum.sort_by(disaccharides, & &1.name))
        }
      end

    children = [mono_node, di_node] |> Enum.reject(&is_nil/1) |> Enum.sort_by(& &1.name)
    children_sum = sum_amounts(children)

    parent = List.first(total_sugars)

    {amount, children_sum} =
      resolve_amounts("Total Sugars", parent && parent.amount, children_sum)

    unit = if parent, do: parent.measurement_unit, else: "g"

    if parent != nil or children != [] do
      node = %{
        name: "Total Sugars",
        amount: amount,
        children_sum: children_sum,
        measurement_unit: unit,
        children: children
      }

      {node, [node | current_children]}
    else
      {nil, current_children}
    end
  end

  defp build_sugar_alcohols(nutrients, current_children) do
    if nutrients != [] do
      parent = Enum.find(nutrients, fn n -> n.name == "Sugar Alcohols" end)
      children = Enum.filter(nutrients, fn n -> n.name != "Sugar Alcohols" end)

      children_sum = sum_amounts(children)

      {amount, children_sum} =
        resolve_amounts("Sugar Alcohols", parent && parent.amount, children_sum)

      unit = if parent, do: parent.measurement_unit, else: "g"

      subcategory = %{
        name: "Sugar Alcohols",
        amount: amount,
        children_sum: children_sum,
        measurement_unit: unit,
        children: convert_to_atom_keys(Enum.sort_by(children, & &1.name))
      }

      {subcategory, [subcategory | current_children]}
    else
      {nil, current_children}
    end
  end

  # ---------------------------------------------------------------------------
  # Fatty acid deduplication
  # ---------------------------------------------------------------------------

  # Groups fatty acids by {prefix, carbon:bonds}.  When a group contains both
  # omega-specific entries (n-3, n-6, …) and generic "c" entries, the generics
  # are dropped — they represent the same molecule without positional detail.
  # Within a group of omega-specific entries, duplicates are further collapsed
  # by {prefix, carbon:bonds, omega}, keeping the highest-specificity name.
  defp deduplicate_fatty_acids(fatty_acids) do
    fatty_acids
    |> Enum.group_by(&fa_base_key/1)
    |> Enum.flat_map(fn {_key, group} ->
      with_omega = Enum.filter(group, &fa_has_omega?/1)

      if with_omega != [] do
        with_omega
        |> Enum.group_by(&fa_omega_key/1)
        |> Enum.map(fn {_, omega_group} ->
          Enum.max_by(omega_group, &fa_specificity/1)
        end)
      else
        [Enum.max_by(group, &fa_specificity/1)]
      end
    end)
  end

  defp fa_base_key(nutrient) do
    name_lower = String.downcase(nutrient.name)
    {fa_prefix(name_lower), fa_extract_cb(name_lower)}
  end

  defp fa_omega_key(nutrient) do
    name_lower = String.downcase(nutrient.name)
    {fa_prefix(name_lower), fa_extract_cb(name_lower), fa_extract_omega(name_lower)}
  end

  defp fa_has_omega?(nutrient) do
    Regex.match?(~r/n-\d/, String.downcase(nutrient.name))
  end

  defp fa_specificity(nutrient) do
    name_lower = String.downcase(nutrient.name)

    [
      {Regex.match?(~r/n-\d/, name_lower), 4},
      {Regex.match?(~r/\([a-z]+\)/, name_lower), 2},
      {String.contains?(name_lower, "c,c"), 1}
    ]
    |> Enum.reduce(0, fn {cond, score}, acc -> if cond, do: acc + score, else: acc end)
  end

  defp fa_prefix(name_lower) do
    cond do
      String.starts_with?(name_lower, "sfa") -> :sfa
      String.starts_with?(name_lower, "mufa") -> :mufa
      String.starts_with?(name_lower, "pufa") -> :pufa
      String.starts_with?(name_lower, "tfa") -> :tfa
      true -> :other
    end
  end

  defp fa_extract_cb(name_lower) do
    case Regex.run(~r/(\d{1,2}:\d{1,2})/, name_lower) do
      [_, cb] -> cb
      nil -> name_lower
    end
  end

  defp fa_extract_omega(name_lower) do
    case Regex.run(~r/(n-\d)/, name_lower) do
      [_, omega] -> omega
      nil -> nil
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Returns {amount, children_sum}.
  # amount = official USDA value when present (logs a warning if it diverges from
  # children_sum beyond 10% or 0.5g); otherwise amount = children_sum.
  defp resolve_amounts(_category_name, nil, children_sum), do: {children_sum, children_sum}

  defp resolve_amounts(category_name, official_amount, children_sum) do
    threshold = max(0.5, official_amount * 0.1)

    if abs(official_amount - children_sum) > threshold do
      Logger.warning(
        "NutrientHierarchyBuilder: #{category_name} official amount #{official_amount} " <>
          "differs from children sum #{Float.round(children_sum * 1.0, 2)} " <>
          "(diff #{Float.round(abs(official_amount - children_sum) * 1.0, 2)})"
      )
    end

    {official_amount, children_sum}
  end

  defp sum_amounts(items) do
    Enum.reduce(items, 0.0, fn item, acc ->
      amount = Map.get(item, :amount) || Map.get(item, "amount") || 0
      acc + amount
    end)
  end

  defp convert_to_atom_keys(data) when is_list(data) do
    Enum.map(data, &convert_to_atom_keys/1)
  end

  defp convert_to_atom_keys(data) when is_map(data) do
    data
    |> Enum.map(fn {key, value} ->
      new_key = if is_binary(key), do: String.to_atom(key), else: key
      {new_key, convert_to_atom_keys(value)}
    end)
    |> Enum.into(%{})
  end

  defp convert_to_atom_keys(other), do: other
end
