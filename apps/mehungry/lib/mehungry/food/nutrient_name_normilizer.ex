defmodule Mehungry.Food.NutrientNameNormalizer do
  @moduledoc """
  Handles normalization of nutrient names to canonical forms.
  Supports fatty acids, vitamins, minerals, and macronutrients.
  """

  @doc """
  Main normalization function - converts any nutrient name to canonical form
  """
  def normalize(name) when is_nil(name), do: "Unknown"
  def normalize(name) when is_atom(name), do: normalize(Atom.to_string(name))

  def normalize(name) when is_binary(name) do
    name_lower = String.downcase(name)
    canonical = get_canonical_name(name, name_lower)

    if is_nil(canonical) do
      # If no canonical form, try to format nicely
      format_name(name)
    else
      canonical
    end
  end

  defp get_canonical_name(original_name, name_lower) do
    cond do
      # ===== ENERGY =====
      String.contains?(name_lower, "energy") or String.contains?(name_lower, "calorie") ->
        "Energy"

      # ===== PROTEIN =====
      String.contains?(name_lower, "protein") ->
        "Protein"

      # ===== CARBOHYDRATES =====
      String.contains?(name_lower, "carbohydrate") ->
        "Carbohydrates"

      # ===== FIBER =====
      # LMWDF and HMWDF are sub-fractions of the total — keep them distinct so
      # they don't get summed with the canonical fiber total and cause double-counting.
      String.contains?(name_lower, "lmwdf") or String.contains?(name_lower, "hmwdf") or
          String.contains?(name_lower, "low molecular weight dietary fiber") or
          String.contains?(name_lower, "high molecular weight dietary fiber") ->
        original_name

      String.contains?(name_lower, "fiber") ->
        "Fiber"

      # ===== SUGARS =====
      String.contains?(name_lower, "sugar") and not String.contains?(name_lower, "added") ->
        "Total Sugars"

      String.contains?(name_lower, "added sugar") ->
        "Added Sugars"

      name_lower in ["glucose", "fructose", "sucrose", "lactose", "maltose", "galactose"] ->
        String.capitalize(name_lower)

      # ===== TOTAL FAT =====
      name_lower in [
        "total lipid (fat)",
        "total fat",
        "fat",
        "lipid",
        "total fat (nlea)",
        "total lipid (fat) (nlea)"
      ] ->
        "Total Fat"

      # ===== SATURATED FAT =====
      name_lower in [
        "fatty acids, total saturated",
        "total saturated fatty acids",
        "saturated fat"
      ] ->
        "Saturated Fat"

      String.starts_with?(name_lower, "sfa") ->
        # Keep SFA as-is for fatty acid identification
        original_name

      # ===== MONOUNSATURATED FAT =====
      name_lower in [
        "fatty acids, total monounsaturated",
        "total monounsaturated fatty acids",
        "monounsaturated fat"
      ] ->
        "Monounsaturated Fat"

      String.starts_with?(name_lower, "mufa") ->
        # Keep MUFA as-is for fatty acid identification
        original_name

      # ===== POLYUNSATURATED FAT =====
      name_lower in [
        "fatty acids, total polyunsaturated",
        "total polyunsaturated fatty acids",
        "polyunsaturated fat"
      ] ->
        "Polyunsaturated Fat"

      String.starts_with?(name_lower, "pufa") ->
        # Keep PUFA as-is for fatty acid identification
        original_name

      # ===== OMEGA-3 FATTY ACIDS =====
      String.contains?(name_lower, "dha") or String.contains?(name_lower, "22:6") ->
        "DHA (Docosahexaenoic Acid, Omega-3)"

      String.contains?(name_lower, "epa") or String.contains?(name_lower, "20:5") ->
        "EPA (Eicosapentaenoic Acid, Omega-3)"

      String.contains?(name_lower, "ala") or
          (String.contains?(name_lower, "18:3") and String.contains?(name_lower, "n-3")) ->
        "ALA (Alpha-Linolenic Acid, Omega-3)"

      # ===== OMEGA-6 FATTY ACIDS =====
      String.contains?(name_lower, "18:2") and String.contains?(name_lower, "n-6") ->
        "Linoleic Acid (Omega-6)"

      String.contains?(name_lower, "20:4") and String.contains?(name_lower, "n-6") ->
        "Arachidonic Acid (Omega-6)"

      # ===== OMEGA-9 FATTY ACIDS =====
      String.contains?(name_lower, "oleic") or
          (String.contains?(name_lower, "18:1") and not String.contains?(name_lower, "n-7")) ->
        "Oleic Acid (Omega-9)"

      # ===== TRANS FAT =====
      name_lower in ["fatty acids, total trans", "trans fat"] ->
        "Trans Fat"

      # ===== CHOLESTEROL =====
      String.contains?(name_lower, "cholesterol") ->
        "Cholesterol"

      # ===== MINERALS =====
      name_lower in ["sodium", "na"] ->
        "Sodium"

      name_lower in ["potassium", "k"] ->
        "Potassium"

      name_lower in ["calcium", "ca"] ->
        "Calcium"

      name_lower in ["iron", "fe"] ->
        "Iron"

      name_lower in ["magnesium", "mg"] ->
        "Magnesium"

      name_lower in ["phosphorus", "p"] ->
        "Phosphorus"

      name_lower in ["zinc", "zn"] ->
        "Zinc"

      name_lower in ["copper", "cu"] ->
        "Copper"

      name_lower in ["manganese", "mn"] ->
        "Manganese"

      name_lower in ["selenium", "se"] ->
        "Selenium"

      # ===== VITAMINS =====
      true ->
        cond do
          String.contains?(name_lower, "vitamin a") -> "Vitamin A"
          String.contains?(name_lower, "vitamin c") -> "Vitamin C"
          String.contains?(name_lower, "vitamin d") -> "Vitamin D"
          String.contains?(name_lower, "vitamin e") -> "Vitamin E"
          String.contains?(name_lower, "vitamin k") -> "Vitamin K"
          String.contains?(name_lower, "vitamin b12") -> "Vitamin B12"
          String.contains?(name_lower, "vitamin b6") -> "Vitamin B6"
          String.contains?(name_lower, "thiamin") -> "Vitamin B1 (Thiamin)"
          String.contains?(name_lower, "riboflavin") -> "Vitamin B2 (Riboflavin)"
          String.contains?(name_lower, "niacin") -> "Vitamin B3 (Niacin)"
          String.contains?(name_lower, "pantothenic") -> "Vitamin B5 (Pantothenic Acid)"
          String.contains?(name_lower, "biotin") -> "Vitamin B7 (Biotin)"
          String.contains?(name_lower, "folate") -> "Folate (Vitamin B9)"
          String.contains?(name_lower, "choline") -> "Choline"
          true -> nil
        end
    end
  end

  defp format_name(name) do
    name
    |> String.split(" ")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  @doc """
  Determines if a nutrient is a fatty acid
  """
  def is_fatty_acid?(name) do
    name_lower = String.downcase(name)

    String.starts_with?(name_lower, "sfa") or
      String.starts_with?(name_lower, "mufa") or
      String.starts_with?(name_lower, "pufa") or
      String.contains?(name_lower, "fatty acid") or
      String.contains?(name_lower, "omega-") or
      Regex.match?(~r/\d+:\d+/, name_lower)
  end

  @doc """
  Determines which fat category a fatty acid belongs to
  """
  def get_fat_category(name) do
    name_lower = String.downcase(name)

    cond do
      String.starts_with?(name_lower, "sfa") or
          (String.contains?(name_lower, "saturated") and
             not String.contains?(name_lower, "polyunsaturated")) ->
        "Saturated Fat"

      String.starts_with?(name_lower, "mufa") or String.contains?(name_lower, "monounsaturated") ->
        "Monounsaturated Fat"

      String.starts_with?(name_lower, "pufa") or String.contains?(name_lower, "polyunsaturated") ->
        "Polyunsaturated Fat"

      String.contains?(name_lower, "trans") ->
        "Trans Fat"

      true ->
        nil
    end
  end
end
