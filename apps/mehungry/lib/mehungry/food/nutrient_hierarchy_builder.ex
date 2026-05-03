defmodule Mehungry.Food.NutrientHierarchyBuilder do
  @moduledoc """
  Builds hierarchical structure for nutrients with proper nesting.
  Supports 3-level hierarchy: Total Fat -> Fat Type -> Individual Fatty Acids
  """

  def build_hierarchy(nutrients) do
    # Start with empty state
    initial_state = %{
      main: %{},
      saturated_fats: [],
      monounsaturated_fats: [],
      polyunsaturated_fats: [],
      trans_fats: [],
      vitamins: [],
      minerals: [],
      sugars: [],
      other: []
    }

    # Categorize each nutrient
    categorized =
      Enum.reduce(nutrients, initial_state, fn nutrient, acc ->
        name = nutrient.name
        name_lower = String.downcase(name)

        cond do
          # ===== MAIN NUTRIENTS =====
          name in ["Energy", "Protein", "Carbohydrates", "Fiber", "Cholesterol"] ->
            %{acc | main: Map.put(acc.main, name, nutrient)}

          # ===== TOTAL FAT =====
          name == "Total Fat" ->
            %{acc | main: Map.put(acc.main, "Total Fat", nutrient)}

          # ===== SATURATED FAT CATEGORY =====
          name == "Saturated Fat" or name == "Fatty Acids, Total Saturated" ->
            %{acc | saturated_fats: [nutrient | acc.saturated_fats]}

          # ===== MONOUNSATURATED FAT CATEGORY =====
          name == "Monounsaturated Fat" or name == "Fatty Acids, Total Monounsaturated" ->
            %{acc | monounsaturated_fats: [nutrient | acc.monounsaturated_fats]}

          # ===== POLYUNSATURATED FAT CATEGORY =====
          name == "Polyunsaturated Fat" or name == "Fatty Acids, Total Polyunsaturated" ->
            %{acc | polyunsaturated_fats: [nutrient | acc.polyunsaturated_fats]}

          # ===== TRANS FAT CATEGORY =====
          name == "Trans Fat" or
            name == "Fatty Acids, Total Trans" or
            name == "Fatty Acids, Total Trans-monoenoic" or
              name == "Fatty Acids, Total Trans-polyenoic" ->
            %{acc | trans_fats: [nutrient | acc.trans_fats]}

          # ===== INDIVIDUAL FATTY ACIDS (will become children of their categories) =====
          String.starts_with?(name_lower, "sfa") ->
            %{acc | saturated_fats: [nutrient | acc.saturated_fats]}

          String.starts_with?(name_lower, "mufa") ->
            %{acc | monounsaturated_fats: [nutrient | acc.monounsaturated_fats]}

          String.starts_with?(name_lower, "pufa") ->
            %{acc | polyunsaturated_fats: [nutrient | acc.polyunsaturated_fats]}

          String.starts_with?(name_lower, "tfa") ->
            %{acc | trans_fats: [nutrient | acc.trans_fats]}

          # ===== SUGARS =====
          name == "Total Sugars" or
            String.contains?(name_lower, "sugar") or
              name in ["Glucose", "Fructose", "Sucrose", "Lactose", "Maltose", "Galactose"] ->
            %{acc | sugars: [nutrient | acc.sugars]}

          # ===== VITAMINS =====
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

          # ===== MINERALS =====
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

          # ===== EVERYTHING ELSE =====
          true ->
            %{acc | other: [nutrient | acc.other]}
        end
      end)

    # Build the result
    build_result(categorized)
  end

  defp build_result(categorized) do
    result = %{}

    # Build fat structure with proper nesting
    total_fat = build_total_fat(categorized)

    result =
      if not is_nil(total_fat) do
        Map.put(result, :total_fat, total_fat)
      else
        result
      end

    # Add other main nutrients
    result =
      Enum.reduce(categorized.main, result, fn {key, nutrient}, acc ->
        if key != "Total Fat" do
          Map.put(acc, String.to_atom(key), convert_to_atom_keys(nutrient))
        else
          acc
        end
      end)

    # Add Vitamins group
    result =
      if categorized.vitamins != [] do
        vitamins_group = %{
          name: "Vitamins",
          amount: Enum.reduce(categorized.vitamins, 0, fn v, acc -> acc + (v.amount || 0) end),
          measurement_unit: "mg",
          children: convert_to_atom_keys(Enum.sort_by(categorized.vitamins, & &1.name))
        }

        Map.put(result, :vitamins, vitamins_group)
      else
        result
      end

    # Add Minerals group
    result =
      if categorized.minerals != [] do
        minerals_group = %{
          name: "Minerals",
          amount: Enum.reduce(categorized.minerals, 0, fn m, acc -> acc + (m.amount || 0) end),
          measurement_unit: "mg",
          children: convert_to_atom_keys(Enum.sort_by(categorized.minerals, & &1.name))
        }

        Map.put(result, :minerals, minerals_group)
      else
        result
      end

    # Add Total Sugars group
    result =
      if categorized.sugars != [] do
        sugars_group = build_sugars_group(categorized.sugars)
        Map.put(result, :total_sugars, sugars_group)
      else
        result
      end

    # Add remaining nutrients
    result =
      Enum.reduce(categorized.other, result, fn nutrient, acc ->
        Map.put(acc, String.to_atom(nutrient.name), convert_to_atom_keys(nutrient))
      end)

    # Convert the entire result to use atom keys
    convert_to_atom_keys(result)
  end

  defp build_total_fat(categorized) do
    # Build each fat subcategory with their individual fatty acids
    fat_subcategories = []

    # Saturated Fat
    {saturated, fat_subcategories} =
      build_fat_subcategory_with_individuals(
        categorized.saturated_fats,
        "Saturated Fat",
        fat_subcategories
      )

    # Monounsaturated Fat
    {monounsaturated, fat_subcategories} =
      build_fat_subcategory_with_individuals(
        categorized.monounsaturated_fats,
        "Monounsaturated Fat",
        fat_subcategories
      )

    # Polyunsaturated Fat
    {polyunsaturated, fat_subcategories} =
      build_fat_subcategory_with_individuals(
        categorized.polyunsaturated_fats,
        "Polyunsaturated Fat",
        fat_subcategories
      )

    # Trans Fat
    {trans, fat_subcategories} =
      build_fat_subcategory_with_individuals(
        categorized.trans_fats,
        "Trans Fat",
        fat_subcategories
      )

    # Get Total Fat parent
    total_fat_parent = Map.get(categorized.main, "Total Fat")

    # Build Total Fat
    if fat_subcategories != [] do
      total_fat_amount =
        Enum.reduce(fat_subcategories, 0, fn child, acc ->
          acc + (child.amount || 0)
        end)

      sorted_children = Enum.sort_by(fat_subcategories, & &1.name)

      if not is_nil(total_fat_parent) do
        %{
          name: total_fat_parent.name,
          amount: total_fat_parent.amount,
          measurement_unit: total_fat_parent.measurement_unit,
          children: convert_to_atom_keys(sorted_children)
        }
      else
        %{
          name: "Total Fat",
          amount: total_fat_amount,
          measurement_unit: "g",
          children: convert_to_atom_keys(sorted_children)
        }
      end
    else
      nil
    end
  end

  # NEW: Build fat subcategory with individual fatty acids as children
  defp build_fat_subcategory_with_individuals(nutrients, category_name, current_children) do
    # Separate parent aggregator from individual fatty acids
    parent = Enum.find(nutrients, fn n -> n.name == category_name end)

    individual_fatty_acids =
      Enum.filter(nutrients, fn n ->
        n.name != category_name and
          not String.contains?(n.name, "Fatty Acids, Total") and
          n.name != "Saturated Fat" and
          n.name != "Monounsaturated Fat" and
          n.name != "Polyunsaturated Fat" and
          n.name != "Trans Fat"
      end)

    # Also include any "Fatty Acids, Total X" as part of the parent if no parent exists
    total_fatty_acids =
      Enum.filter(nutrients, fn n ->
        String.contains?(n.name, "Fatty Acids, Total") and
          n.name != "Fatty Acids, Total Saturated" and
          n.name != "Fatty Acids, Total Monounsaturated" and
          n.name != "Fatty Acids, Total Polyunsaturated" and
          n.name != "Fatty Acids, Total Trans" and
          n.name != "Fatty Acids, Total Trans-monoenoic" and
          n.name != "Fatty Acids, Total Trans-polyenoic"
      end)

    all_children = individual_fatty_acids ++ total_fatty_acids

    if parent != nil or all_children != [] do
      total_amount =
        if parent != nil do
          parent.amount
        else
          Enum.reduce(all_children, 0, fn n, acc -> acc + (n.amount || 0) end)
        end

      # Create human-readable names for common fatty acids
      enhanced_children =
        Enum.map(all_children, fn fatty_acid ->
          enhanced_name = get_fatty_acid_display_name(fatty_acid.name)

          %{
            name: enhanced_name,
            amount: fatty_acid.amount,
            measurement_unit: fatty_acid.measurement_unit,
            # Keep original for reference
            original_name: fatty_acid.name
          }
        end)

      subcategory =
        if parent != nil do
          %{
            name: category_name,
            amount: parent.amount,
            measurement_unit: parent.measurement_unit,
            children: convert_to_atom_keys(Enum.sort_by(enhanced_children, & &1.name))
          }
        else
          %{
            name: category_name,
            amount: total_amount,
            measurement_unit: "g",
            children: convert_to_atom_keys(Enum.sort_by(enhanced_children, & &1.name))
          }
        end

      {subcategory, [subcategory | current_children]}
    else
      {nil, current_children}
    end
  end

  # Helper to create human-readable names for fatty acids
  defp get_fatty_acid_display_name(name) do
    name_lower = String.downcase(name)

    cond do
      # Omega-3s
      String.contains?(name_lower, "22:6") or String.contains?(name_lower, "dha") ->
        "DHA (Docosahexaenoic Acid, Omega-3)"

      String.contains?(name_lower, "20:5") or String.contains?(name_lower, "epa") ->
        "EPA (Eicosapentaenoic Acid, Omega-3)"

      String.contains?(name_lower, "18:3") and String.contains?(name_lower, "n-3") ->
        "ALA (Alpha-Linolenic Acid, Omega-3)"

      # Omega-6s
      String.contains?(name_lower, "18:2") and String.contains?(name_lower, "n-6") ->
        "Linoleic Acid (Omega-6)"

      String.contains?(name_lower, "20:4") and String.contains?(name_lower, "n-6") ->
        "Arachidonic Acid (Omega-6)"

      # Common fatty acids
      String.contains?(name_lower, "16:0") and String.contains?(name_lower, "sfa") ->
        "Palmitic Acid (C16:0)"

      String.contains?(name_lower, "18:0") and String.contains?(name_lower, "sfa") ->
        "Stearic Acid (C18:0)"

      String.contains?(name_lower, "18:1") and String.contains?(name_lower, "mufa") ->
        "Oleic Acid (Omega-9)"

      true ->
        # Format nicely: "Pufa 18:2 N-6 C,C" -> "PUFA 18:2 n-6"
        name
        |> String.split(" ")
        |> Enum.map(&String.capitalize/1)
        |> Enum.join(" ")
    end
  end

  defp build_sugars_group(sugars) do
    total_sugars = Enum.filter(sugars, fn s -> s.name == "Total Sugars" end)
    individual_sugars = Enum.filter(sugars, fn s -> s.name != "Total Sugars" end)

    if total_sugars != [] do
      total = List.first(total_sugars)

      %{
        name: total.name,
        amount: total.amount,
        measurement_unit: total.measurement_unit,
        children: convert_to_atom_keys(Enum.sort_by(individual_sugars, & &1.name))
      }
    else
      total_amount = Enum.reduce(individual_sugars, 0, fn s, acc -> acc + (s.amount || 0) end)

      %{
        name: "Total Sugars",
        amount: total_amount,
        measurement_unit: "g",
        children: convert_to_atom_keys(Enum.sort_by(individual_sugars, & &1.name))
      }
    end
  end

  # Helper to convert string keys to atom keys recursively
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
