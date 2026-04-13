defmodule MehungryWeb.NutrientsHelper do
  @lookup %{
    # VITAMINS
    "vitamin a" => "vitamin a",
    "retinol" => "vitamin a",
    "retinal" => "vitamin a",
    "retinoic acid" => "vitamin a",
    "vit a" => "vitamin a",
    "preformed vitamin a" => "vitamin a",
    "vitamin c" => "vitamin c",
    "ascorbic acid" => "vitamin c",
    "vit c" => "vitamin c",
    "l-ascorbic acid" => "vitamin c",
    "vitamin d" => "vitamin d",
    "cholecalciferol" => "vitamin d",
    "ergocalciferol" => "vitamin d",
    "vit d" => "vitamin d",
    "vitamin d3" => "vitamin d",
    "vitamin d2" => "vitamin d",
    "vitamin e" => "vitamin e",
    "alpha tocopherol" => "vitamin e",
    "tocopherol" => "vitamin e",
    "vit e" => "vitamin e",
    "vitamin k" => "vitamin k",
    "phylloquinone" => "vitamin k",
    "menaquinone" => "vitamin k",
    "vit k" => "vitamin k",
    "vitamin k1" => "vitamin k",
    "vitamin k2" => "vitamin k",
    "vitamin b1" => "vitamin b1",
    "thiamine" => "vitamin b1",
    "thiamin" => "vitamin b1",
    "vit b1" => "vitamin b1",
    "vitamin b2" => "vitamin b2",
    "riboflavin" => "vitamin b2",
    "vit b2" => "vitamin b2",
    "vitamin b3" => "vitamin b3",
    "niacin" => "vitamin b3",
    "nicotinic acid" => "vitamin b3",
    "niacinamide" => "vitamin b3",
    "vit b3" => "vitamin b3",
    "vitamin b5" => "vitamin b5",
    "pantothenic acid" => "vitamin b5",
    "vit b5" => "vitamin b5",
    "vitamin b6" => "vitamin b6",
    "pyridoxine" => "vitamin b6",
    "pyridoxal" => "vitamin b6",
    "pyridoxamine" => "vitamin b6",
    "vit b6" => "vitamin b6",
    "vitamin b7" => "vitamin b7",
    "biotin" => "vitamin b7",
    "vit b7" => "vitamin b7",
    "vitamin b9" => "vitamin b9",
    "folate" => "vitamin b9",
    "folic acid" => "vitamin b9",
    "vit b9" => "vitamin b9",
    "vitamin b12" => "vitamin b12",
    "cobalamin" => "vitamin b12",
    "cyanocobalamin" => "vitamin b12",
    "methylcobalamin" => "vitamin b12",
    "vit b12" => "vitamin b12",

    # MINERALS
    "iron" => "iron",
    "fe" => "iron",
    "ferrum" => "iron",
    "calcium" => "calcium",
    "ca" => "calcium",
    "magnesium" => "magnesium",
    "mg" => "magnesium",
    "potassium" => "potassium",
    "k" => "potassium",
    "sodium" => "sodium",
    "na" => "sodium",
    "zinc" => "zinc",
    "zn" => "zinc",
    "phosphorus" => "phosphorus",
    "p" => "phosphorus",
    "phosphate" => "phosphorus",
    "iodine" => "iodine",
    "iodide" => "iodine",
    "selenium" => "selenium",
    "se" => "selenium",
    "copper" => "copper",
    "cu" => "copper",
    "manganese" => "manganese",
    "mn" => "manganese",

    # MACROS
    "protein" => "protein",
    "proteins" => "protein",
    "fat" => "fat",
    "lipid" => "fat",
    "total fat" => "fat",
    "carbohydrates" => "carbohydrates",
    "carbs" => "carbohydrates",
    "total carbohydrate" => "carbohydrates",
    "fiber" => "fiber",
    "dietary fiber" => "fiber",
    "fibre" => "fiber",
    "sugars" => "sugars",
    "sugar" => "sugars",
    "total sugars" => "sugars",

    # FATS
    "omega 3" => "omega 3",
    "omega-3" => "omega 3",
    "n-3 fatty acids" => "omega 3",
    "alpha-linolenic acid" => "omega 3",
    "epa" => "omega 3",
    "dha" => "omega 3",
    "omega 6" => "omega 6",
    "omega-6" => "omega 6",
    "n-6 fatty acids" => "omega 6",
    "linoleic acid" => "omega 6",
    "arachidonic acid" => "omega 6",
    "saturated fat" => "saturated fat",
    "sfa" => "saturated fat",
    "saturated fatty acids" => "saturated fat",
    "monounsaturated fat" => "monounsaturated fat",
    "mufa" => "monounsaturated fat",
    "monounsaturated fatty acids" => "monounsaturated fat",
    "polyunsaturated fat" => "polyunsaturated fat",
    "pufa" => "polyunsaturated fat",
    "polyunsaturated fatty acids" => "polyunsaturated fat",

    # OTHER
    "cholesterol" => "cholesterol",
    "chol" => "cholesterol",
    "calories" => "calories",
    "energy" => "calories",
    "kcal" => "calories"
  }

  def normalize(str) do
    str
    |> String.downcase()
    |> String.trim()
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/[^a-z0-9\s]/u, "")
  end

  def parse_fatty_acid(term) do
    regex = ~r/^(pufa|mufa|sfa)\s*(\d+):(\d+)/i

    case Regex.run(regex, String.downcase(term)) do
      [_, type, carbons, double_bonds] ->
        {type, String.to_integer(carbons), String.to_integer(double_bonds)}

      _ ->
        nil
    end
  end

  def fatty_acid_to_human({"pufa", 18, 2}), do: "omega 6"
  def fatty_acid_to_human({"pufa", 18, 3}), do: "omega 3"
  def fatty_acid_to_human({"mufa", 18, 1}), do: "monounsaturated fat"
  def fatty_acid_to_human({"sfa", _, _}), do: "saturated fat"

  def fatty_acid_to_human({"pufa", _, _}), do: "polyunsaturated fat"
  def fatty_acid_to_human({"mufa", _, _}), do: "monounsaturated fat"
  def fatty_acid_to_human({"sfa", _, _}), do: "saturated fat"

  def resolve_nutrient(term) do
    normalized = normalize(term)

    cond do
      # 1. direct lookup
      Map.has_key?(@lookup, normalized) ->
        @lookup[normalized]

      # 2. fatty acid pattern
      parsed = parse_fatty_acid(normalized) ->
        fatty_acid_to_human(parsed)

      # 3. fallback
      true ->
        term
    end
  end
end
