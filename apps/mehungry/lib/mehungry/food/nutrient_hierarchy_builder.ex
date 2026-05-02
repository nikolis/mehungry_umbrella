defmodule Mehungry.Food.NutrientHierarchyBuilder do
  @moduledoc """
  Builds hierarchical structure for nutrients with proper nesting.
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
    categorized = Enum.reduce(nutrients, initial_state, fn nutrient, acc ->
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
        
        # ===== INDIVIDUAL SATURATED FATTY ACIDS =====
        String.starts_with?(name_lower, "sfa") ->
          %{acc | saturated_fats: [nutrient | acc.saturated_fats]}
        
        # ===== INDIVIDUAL MONOUNSATURATED FATTY ACIDS =====
        String.starts_with?(name_lower, "mufa") ->
          %{acc | monounsaturated_fats: [nutrient | acc.monounsaturated_fats]}
        
        # ===== INDIVIDUAL POLYUNSATURATED FATTY ACIDS =====
        String.starts_with?(name_lower, "pufa") ->
          %{acc | polyunsaturated_fats: [nutrient | acc.polyunsaturated_fats]}
        
        # ===== INDIVIDUAL TRANS FATTY ACIDS =====
        String.starts_with?(name_lower, "tfa") ->
          %{acc | trans_fats: [nutrient | acc.trans_fats]}
        
        # ===== SUGARS =====
        name == "Total Sugars" or
        String.contains?(name_lower, "sugar") or
        name in ["Glucose", "Fructose", "Sucrose", "Lactose", "Maltose", "Galactose"] ->
          %{acc | sugars: [nutrient | acc.sugars]}
        
        # ===== VITAMINS =====
        String.contains?(name_lower, "vitamin") or
        name in ["Folate", "Choline", "Niacin", "Riboflavin", "Thiamin", "Pantothenic Acid",
                 "Carotene, Alpha", "Carotene, Beta", "Retinol"] ->
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
    
    # Build fat structure
    total_fat = build_total_fat(categorized)
    result = if not is_nil(total_fat) do
      Map.put(result, "Total Fat", total_fat)
    else
      result
    end
    
    # Add other main nutrients (excluding Total Fat since we already added it)
    result = Enum.reduce(categorized.main, result, fn {key, nutrient}, acc ->
      if key != "Total Fat" do
        Map.put(acc, key, nutrient)
      else
        acc
      end
    end)
    
    # Add Vitamins group
    result = if categorized.vitamins != [] do
      vitamins_group = %{
        name: "Vitamins",
        amount: Enum.reduce(categorized.vitamins, 0, fn v, acc -> acc + (v.amount || 0) end),
        measurement_unit: "mg",
        children: Enum.sort_by(categorized.vitamins, & &1.name)
      }
      Map.put(result, "Vitamins", vitamins_group)
    else
      result
    end
    
    # Add Minerals group
    result = if categorized.minerals != [] do
      minerals_group = %{
        name: "Minerals",
        amount: Enum.reduce(categorized.minerals, 0, fn m, acc -> acc + (m.amount || 0) end),
        measurement_unit: "mg",
        children: Enum.sort_by(categorized.minerals, & &1.name)
      }
      Map.put(result, "Minerals", minerals_group)
    else
      result
    end
    
    # Add Total Sugars group
    result = if categorized.sugars != [] do
      sugars_group = build_sugars_group(categorized.sugars)
      Map.put(result, "Total Sugars", sugars_group)
    else
      result
    end
    
    # Add remaining nutrients
    result = Enum.reduce(categorized.other, result, fn nutrient, acc ->
      Map.put(acc, nutrient.name, nutrient)
    end)
    
    result
  end

  defp build_total_fat(categorized) do
    # Build each fat subcategory
    fat_subcategories = []
    
    # Saturated Fat
    {saturated, fat_subcategories} = build_fat_subcategory(
      categorized.saturated_fats,
      "Saturated Fat",
      fat_subcategories
    )
    
    # Monounsaturated Fat
    {monounsaturated, fat_subcategories} = build_fat_subcategory(
      categorized.monounsaturated_fats,
      "Monounsaturated Fat",
      fat_subcategories
    )
    
    # Polyunsaturated Fat
    {polyunsaturated, fat_subcategories} = build_fat_subcategory(
      categorized.polyunsaturated_fats,
      "Polyunsaturated Fat",
      fat_subcategories
    )
    
    # Trans Fat
    {trans, fat_subcategories} = build_fat_subcategory(
      categorized.trans_fats,
      "Trans Fat",
      fat_subcategories
    )
    
    # Get Total Fat parent
    total_fat_parent = Map.get(categorized.main, "Total Fat")
    
    # Build Total Fat
    if fat_subcategories != [] do
      total_fat_amount = Enum.reduce(fat_subcategories, 0, fn child, acc -> 
        acc + (child.amount || 0) 
      end)
      sorted_children = Enum.sort_by(fat_subcategories, & &1.name)
      
      if not is_nil(total_fat_parent) do
        %{total_fat_parent | children: sorted_children}
      else
        %{
          name: "Total Fat",
          amount: total_fat_amount,
          measurement_unit: "g",
          children: sorted_children
        }
      end
    else
      nil
    end
  end

  defp build_fat_subcategory(nutrients, category_name, current_children) do
    # Separate parent from children
    parent = Enum.find(nutrients, fn n -> n.name == category_name end)
    children = Enum.filter(nutrients, fn n -> n.name != category_name end)
    
    if parent != nil or children != [] do
      total_amount = Enum.reduce(nutrients, 0, fn n, acc -> acc + (n.amount || 0) end)
      
      subcategory = if parent != nil do
        %{parent | children: Enum.sort_by(children, & &1.name)}
      else
        %{
          name: category_name,
          amount: total_amount,
          measurement_unit: "g",
          children: Enum.sort_by(children, & &1.name)
        }
      end
      
      {subcategory, [subcategory | current_children]}
    else
      {nil, current_children}
    end
  end

  defp build_sugars_group(sugars) do
    # Separate total sugars from individual sugars
    total_sugars = Enum.filter(sugars, fn s -> s.name == "Total Sugars" end)
    individual_sugars = Enum.filter(sugars, fn s -> s.name != "Total Sugars" end)
    
    if total_sugars != [] do
      total = List.first(total_sugars)
      %{total | children: Enum.sort_by(individual_sugars, & &1.name)}
    else
      total_amount = Enum.reduce(individual_sugars, 0, fn s, acc -> acc + (s.amount || 0) end)
      %{
        name: "Total Sugars",
        amount: total_amount,
        measurement_unit: "g",
        children: Enum.sort_by(individual_sugars, & &1.name)
      }
    end
  end
end
