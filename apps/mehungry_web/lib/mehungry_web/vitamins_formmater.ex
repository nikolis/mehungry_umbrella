defmodule MehungryWeb.VitaminsFormatter do
  @moduledoc """
  Formats all nutrient types (vitamins, minerals, amino acids, etc.) 
  into human-readable names with context about food sources and functions.
  """

  @doc """
  Main entry point for formatting any nutrient to human-readable name
  """
  def format(nutrient_id, nutrient_name \\ nil)
      when is_binary(nutrient_id) or is_number(nutrient_id) do
    id = to_string(nutrient_id)
    name = nutrient_name || ""

    cond do
      # Vitamin A and Carotenoids
      id in ["1104", "1105", "1106", "1107", "1108", "1109"] or
          String.contains?(name, "Vitamin A") ->
        format_vitamin_a(id, name)

      # Vitamin B Complex
      id in ["1110", "1111", "1112", "1113", "1114", "1115", "1116", "1117", "1118", "1119"] or
          String.contains?(
            name,
            ~r/Vitamin B|Thiamin|Riboflavin|Niacin|B6|B12|Folate|Biotin|Pantothenic/
          ) ->
        format_vitamin_b(id, name)

      # Vitamin C
      id == "1162" or String.contains?(name, "Vitamin C") ->
        format_vitamin_c(id, name)

      # Vitamin D
      id in ["1110", "1111", "1112"] or String.contains?(name, "Vitamin D") ->
        format_vitamin_d(id, name)

      # Vitamin E
      id in ["1158", "1159", "1160", "1161"] or String.contains?(name, "Vitamin E") ->
        format_vitamin_e(id, name)

      # Vitamin K
      id in ["1184", "1185"] or String.contains?(name, "Vitamin K") ->
        format_vitamin_k(id, name)

      # Minerals
      id in [
        "1087",
        "1088",
        "1089",
        "1090",
        "1091",
        "1092",
        "1093",
        "1094",
        "1095",
        "1096",
        "1097",
        "1098"
      ] or
          String.contains?(
            name,
            ~r/Calcium|Iron|Magnesium|Potassium|Sodium|Zinc|Copper|Manganese|Selenium|Phosphorus|Iodine|Chromium/
          ) ->
        format_mineral(id, name)

      # Amino Acids
      id in [
        "1210",
        "1211",
        "1212",
        "1213",
        "1214",
        "1215",
        "1216",
        "1217",
        "1218",
        "1219",
        "1220",
        "1221",
        "1222",
        "1223",
        "1224",
        "1225",
        "1226",
        "1227",
        "1228",
        "1229"
      ] or
          String.contains?(
            name,
            ~r/Alanine|Arginine|Aspartic|Cystine|Glutamic|Glycine|Histidine|Isoleucine|Leucine|Lysine|Methionine|Phenylalanine|Proline|Serine|Threonine|Tryptophan|Tyrosine|Valine/
          ) ->
        format_amino_acid(id, name)

      # Energy and Macros
      id in ["1008", "1003", "1004", "1005", "1006", "1007"] or
          String.contains?(name, ~r/Energy|Protein|Fat|Carbohydrate|Fiber|Sugar/) ->
        format_macro(id, name)

      # Default
      true ->
        format_generic(id, name)
    end
  end

  # ============================================================================
  # VITAMIN A & CAROTENOIDS
  # ============================================================================

  defp format_vitamin_a(id, name) do
    name_lower = String.downcase(name)

    cond do
      id == "1104" or String.contains?(name_lower, "retinol") ->
        "Vitamin A (Retinol) • Animal source • Essential for vision and immune function"

      id == "1105" or String.contains?(name_lower, "beta-carotene") ->
        "Beta-Carotene • Plant source • Converted to Vitamin A in body • Found in carrots, sweet potatoes"

      id == "1106" or String.contains?(name_lower, "alpha-carotene") ->
        "Alpha-Carotene • Plant source • Found in pumpkins, carrots"

      id == "1107" or String.contains?(name_lower, "cryptoxanthin") ->
        "Beta-Cryptoxanthin • Plant source • Found in oranges, papaya"

      id == "1108" or String.contains?(name_lower, "vitamin a") ->
        "Vitamin A (Total) • Essential for vision, immune function, and cell growth"

      id == "1109" or String.contains?(name_lower, "lycopene") ->
        "Lycopene • Powerful antioxidant • Found in tomatoes, watermelon"

      String.contains?(name_lower, "carotene") ->
        "Carotenoid • Plant pigment with antioxidant properties"

      true ->
        "Vitamin A • Essential fat-soluble vitamin"
    end
  end

  # ============================================================================
  # VITAMIN B COMPLEX
  # ============================================================================

  defp format_vitamin_b(id, name) do
    name_lower = String.downcase(name)

    cond do
      id == "1110" or String.contains?(name_lower, "thiamin") ->
        "Vitamin B1 (Thiamin) • Energy metabolism • Found in whole grains, pork, beans"

      id == "1111" or String.contains?(name_lower, "riboflavin") ->
        "Vitamin B2 (Riboflavin) • Energy production • Found in dairy, eggs, almonds"

      id == "1112" or String.contains?(name_lower, "niacin") ->
        "Vitamin B3 (Niacin) • DNA repair • Found in chicken, turkey, peanuts"

      id == "1113" or String.contains?(name_lower, "pantothenic") ->
        "Vitamin B5 (Pantothenic Acid) • Hormone synthesis • Found in avocados, mushrooms"

      id == "1114" or String.contains?(name_lower, "b6") ->
        "Vitamin B6 (Pyridoxine) • Brain development • Found in chickpeas, bananas, potatoes"

      id in ["1115", "1116"] or String.contains?(name_lower, "biotin") ->
        "Vitamin B7 (Biotin) • Hair and nail health • Found in eggs, nuts, sweet potatoes"

      id in ["1117", "1118"] or String.contains?(name_lower, "folate") ->
        "Vitamin B9 (Folate/Folic Acid) • DNA synthesis • Crucial during pregnancy • Found in leafy greens, beans"

      id in ["1119", "1120"] or String.contains?(name_lower, "b12") ->
        "Vitamin B12 (Cobalamin) • Nerve health • Found in meat, fish, dairy • Not naturally in plants"

      true ->
        "Vitamin B Complex • Essential for metabolism and cell health"
    end
  end

  # ============================================================================
  # VITAMIN C
  # ============================================================================

  defp format_vitamin_c(id, name) do
    cond do
      id == "1162" or String.contains?(String.downcase(name), "ascorbic") ->
        "Vitamin C (Ascorbic Acid) • Powerful antioxidant • Immune support • Found in citrus, peppers, strawberries"

      true ->
        "Vitamin C • Essential for collagen production and immunity"
    end
  end

  # ============================================================================
  # VITAMIN D
  # ============================================================================

  defp format_vitamin_d(id, name) do
    name_lower = String.downcase(name)

    cond do
      id == "1110" or String.contains?(name_lower, "d2") ->
        "Vitamin D2 (Ergocalciferol) • Plant source • Found in mushrooms"

      id == "1111" or String.contains?(name_lower, "d3") ->
        "Vitamin D3 (Cholecalciferol) • Animal source • Produced from sunlight • Found in fatty fish, egg yolks"

      true ->
        "Vitamin D • Bone health • Immune function • The 'sunshine vitamin'"
    end
  end

  # ============================================================================
  # VITAMIN E
  # ============================================================================

  defp format_vitamin_e(id, name) do
    name_lower = String.downcase(name)

    cond do
      id == "1158" or String.contains?(name_lower, "alpha-tocopherol") ->
        "Vitamin E (Alpha-Tocopherol) • Most active form • Antioxidant • Found in nuts, seeds, spinach"

      id in ["1159", "1160", "1161"] ->
        "Vitamin E (Tocopherols) • Antioxidant family • Protects cell membranes"

      true ->
        "Vitamin E • Fat-soluble antioxidant • Supports immune function"
    end
  end

  # ============================================================================
  # VITAMIN K
  # ============================================================================

  defp format_vitamin_k(id, name) do
    name_lower = String.downcase(name)

    cond do
      id == "1184" or String.contains?(name_lower, "k1") ->
        "Vitamin K1 (Phylloquinone) • Blood clotting • Found in leafy greens (kale, spinach)"

      id == "1185" or String.contains?(name_lower, "k2") ->
        "Vitamin K2 (Menaquinone) • Bone health • Found in fermented foods, natto, cheese"

      true ->
        "Vitamin K • Essential for blood clotting and bone metabolism"
    end
  end

  # ============================================================================
  # MINERALS
  # ============================================================================

  defp format_mineral(id, name) do
    name_lower = String.downcase(name)

    cond do
      id == "1087" or String.contains?(name_lower, "calcium") ->
        "Calcium • Bone and teeth health • Muscle function • Found in dairy, leafy greens, fortified foods"

      id == "1088" or String.contains?(name_lower, "chromium") ->
        "Chromium • Blood sugar regulation • Found in broccoli, grapes, whole grains"

      id == "1089" or String.contains?(name_lower, "iron") ->
        "Iron • Oxygen transport • Energy production • Heme (animal) and non-heme (plant) sources"

      id == "1090" or String.contains?(name_lower, "magnesium") ->
        "Magnesium • 300+ enzymatic reactions • Muscle relaxation • Found in nuts, seeds, dark chocolate"

      id == "1091" or String.contains?(name_lower, "phosphorus") ->
        "Phosphorus • Bone health • Energy production • Found in dairy, meat, whole grains"

      id == "1092" or String.contains?(name_lower, "potassium") ->
        "Potassium • Blood pressure regulation • Fluid balance • Found in bananas, potatoes, avocados"

      id == "1093" or String.contains?(name_lower, "sodium") ->
        "Sodium • Fluid balance • Nerve transmission • Consume in moderation"

      id == "1094" or String.contains?(name_lower, "zinc") ->
        "Zinc • Immune function • Wound healing • Found in oysters, meat, pumpkin seeds"

      id == "1095" or String.contains?(name_lower, "copper") ->
        "Copper • Iron metabolism • Collagen formation • Found in shellfish, nuts, organ meats"

      id == "1096" or String.contains?(name_lower, "manganese") ->
        "Manganese • Bone formation • Blood clotting • Found in whole grains, nuts, tea"

      id == "1097" or String.contains?(name_lower, "selenium") ->
        "Selenium • Antioxidant • Thyroid function • Found in Brazil nuts, seafood, eggs"

      id == "1098" or String.contains?(name_lower, "iodine") ->
        "Iodine • Thyroid hormone production • Found in seaweed, iodized salt, fish"

      true ->
        "Mineral • Essential for body functions"
    end
  end

  # ============================================================================
  # AMINO ACIDS
  # ============================================================================

  defp format_amino_acid(id, name) do
    name_lower = String.downcase(name)

    # Essential vs Non-essential mapping
    essentials = [
      "histidine",
      "isoleucine",
      "leucine",
      "lysine",
      "methionine",
      "phenylalanine",
      "threonine",
      "tryptophan",
      "valine"
    ]

    is_essential = Enum.any?(essentials, &String.contains?(name_lower, &1))

    essential_note =
      if is_essential,
        do: " • Essential • Must obtain from food",
        else: " • Non-essential • Body can produce"

    cond do
      String.contains?(name_lower, "alanine") ->
        "Alanine • Energy metabolism • Supports immune system#{essential_note}"

      String.contains?(name_lower, "arginine") ->
        "Arginine • Wound healing • Growth hormone release • Found in nuts, seeds#{essential_note}"

      String.contains?(name_lower, "asparagine") ->
        "Asparagine • Nervous system function#{essential_note}"

      String.contains?(name_lower, "aspartic") ->
        "Aspartic Acid • Energy production • Neurotransmitter#{essential_note}"

      String.contains?(name_lower, "cysteine") ->
        "Cysteine • Antioxidant (glutathione precursor) • Found in poultry, yogurt#{essential_note}"

      String.contains?(name_lower, "glutamic") ->
        "Glutamic Acid • Brain function • Precursor to GABA#{essential_note}"

      String.contains?(name_lower, "glutamine") ->
        "Glutamine • Gut health • Immune function • Most abundant amino acid#{essential_note}"

      String.contains?(name_lower, "glycine") ->
        "Glycine • Collagen production • Sleep quality • Found in bone broth#{essential_note}"

      String.contains?(name_lower, "histidine") ->
        "Histidine • Histamine production • Tissue repair • Found in meat, fish#{essential_note}"

      String.contains?(name_lower, "isoleucine") ->
        "Isoleucine • Muscle repair • Blood sugar regulation • Branched-chain#{essential_note}"

      String.contains?(name_lower, "leucine") ->
        "Leucine • Muscle protein synthesis • Branched-chain • Key for exercise recovery#{essential_note}"

      String.contains?(name_lower, "lysine") ->
        "Lysine • Calcium absorption • Collagen production • Found in meat, eggs#{essential_note}"

      String.contains?(name_lower, "methionine") ->
        "Methionine • Detoxification • Fat metabolism • Found in eggs, fish#{essential_note}"

      String.contains?(name_lower, "phenylalanine") ->
        "Phenylalanine • Dopamine production • Mood regulation • Found in dairy, meat#{essential_note}"

      String.contains?(name_lower, "proline") ->
        "Proline • Collagen stability • Wound healing#{essential_note}"

      String.contains?(name_lower, "serine") ->
        "Serine • Cell signaling • Nervous system function#{essential_note}"

      String.contains?(name_lower, "threonine") ->
        "Threonine • Immune function • Gut health • Found in poultry, dairy#{essential_note}"

      String.contains?(name_lower, "tryptophan") ->
        "Tryptophan • Serotonin production • Sleep regulation • Found in turkey, pumpkin seeds#{essential_note}"

      String.contains?(name_lower, "tyrosine") ->
        "Tyrosine • Dopamine & thyroid production • Found in cheese, soy#{essential_note}"

      String.contains?(name_lower, "valine") ->
        "Valine • Muscle metabolism • Branched-chain • Energy production#{essential_note}"

      true ->
        "Amino Acid • Protein building block#{essential_note}"
    end
  end

  # ============================================================================
  # MACRONUTRIENTS
  # ============================================================================

  defp format_macro(id, name) do
    name_lower = String.downcase(name)

    cond do
      id == "1008" or String.contains?(name_lower, "energy") ->
        "Energy (Calories) • Fuel for body activities"

      id == "1003" or String.contains?(name_lower, "protein") ->
        "Protein • Builds and repairs tissues • Essential for growth"

      id == "1004" or
          (String.contains?(name_lower, "fat") and not String.contains?(name_lower, "saturated")) ->
        "Total Fat • Energy storage • Vitamin absorption • Essential fatty acids"

      id == "1005" or String.contains?(name_lower, "carbohydrate") ->
        "Carbohydrates • Primary energy source • 4 calories per gram"

      id == "1079" or String.contains?(name_lower, "fiber") ->
        "Dietary Fiber • Digestive health • Blood sugar regulation • Heart health"

      id == "2000" or String.contains?(name_lower, "sugar") ->
        "Total Sugars • Simple carbohydrates • Natural and added"

      true ->
        "Macronutrient • Essential for energy and body function"
    end
  end

  # ============================================================================
  # GENERIC FALLBACK
  # ============================================================================

  defp format_generic(id, name) do
    # Try to clean up the USDA name if available
    if name != "" do
      name
      |> String.replace("_", " ")
      |> String.trim()
      |> capitalize_properly()
    else
      "Nutrient #{id}"
    end
  end

  defp capitalize_properly(string) do
    string
    |> String.split(" ")
    |> Enum.map(fn word ->
      case String.downcase(word) do
        "and" -> "and"
        "of" -> "of"
        "in" -> "in"
        "to" -> "to"
        "for" -> "for"
        "with" -> "with"
        "by" -> "by"
        "a" -> "a"
        "an" -> "an"
        "the" -> "the"
        other -> String.capitalize(other)
      end
    end)
    |> Enum.join(" ")
  end
end
