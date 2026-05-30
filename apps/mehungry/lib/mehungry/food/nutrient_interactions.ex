defmodule Mehungry.Food.NutrientInteractions do
  @moduledoc """
  Detects nutrient interactions across a set of ingredients.

  Rules are encoded as static data — this is established biochemistry that
  changes rarely. Each rule names two canonical nutrients (from
  NutrientNameNormalizer) and a relationship type:

    :enhances  — nutrient_b improves absorption/utilisation of nutrient_a
    :inhibits  — nutrient_b reduces absorption of nutrient_a
    :requires  — nutrient_a needs nutrient_b present to be absorbed at all

  Thresholds define the minimum amount per 100 g of an ingredient for that
  nutrient to be considered "significant". Values are based on 10% of the
  FDA daily value unless otherwise noted.

  Sources: NIH Office of Dietary Supplements, EFSA scientific opinions,
  peer-reviewed literature (cited per rule).
  """

  import Ecto.Query
  alias Mehungry.Repo
  alias Mehungry.Food.{IngredientNutrient, Nutrient}
  alias Mehungry.Food.NutrientNameNormalizer

  # Minimum amount per 100 g to treat a nutrient as "significant".
  # Based on 10% of FDA daily value unless noted.
  @thresholds %{
    "Iron"        => 1.8,    # 10% of 18 mg DV
    "Calcium"     => 130.0,  # 10% of 1300 mg DV
    "Vitamin C"   => 9.0,    # 10% of 90 mg DV
    "Vitamin D"   => 2.0,    # 10% of 20 µg DV
    "Vitamin A"   => 90.0,   # 10% of 900 µg DV
    "Vitamin E"   => 1.5,    # 10% of 15 mg DV
    "Vitamin K"   => 12.0,   # 10% of 120 µg DV
    "Zinc"        => 1.1,    # 10% of 11 mg DV
    "Total Fat"   => 5.0,    # meaningful fat content
    "Magnesium"   => 42.0,   # 10% of 420 mg DV
    "Folate (Vitamin B9)" => 40.0  # 10% of 400 µg DV
  }

  @rules [
    %{
      id: :vitamin_c_enhances_iron,
      type: :enhances,
      nutrient_a: "Iron",
      nutrient_b: "Vitamin C",
      badge: :positive,
      label: "Boosts iron absorption",
      detail:
        "Vitamin C converts non-heme iron to a more absorbable form, " <>
          "increasing uptake by up to 3×.",
      source: "Hunt JR, 2003 – Am J Clin Nutr"
    },
    %{
      id: :calcium_inhibits_iron,
      type: :inhibits,
      nutrient_a: "Iron",
      nutrient_b: "Calcium",
      badge: :warning,
      label: "Reduces iron absorption",
      detail:
        "Calcium competes with iron for intestinal transport. " <>
          "Consider separating these ingredients at different meals.",
      source: "Hallberg et al., 1991 – Am J Clin Nutr"
    },
    %{
      id: :zinc_inhibits_iron,
      type: :inhibits,
      nutrient_a: "Iron",
      nutrient_b: "Zinc",
      badge: :warning,
      label: "May compete with iron",
      detail:
        "High zinc intake can reduce non-heme iron absorption " <>
          "when consumed at the same time.",
      source: "Solomons NW, 1986 – J Nutr"
    },
    %{
      id: :vitamin_d_enhances_calcium,
      type: :enhances,
      nutrient_a: "Calcium",
      nutrient_b: "Vitamin D",
      badge: :positive,
      label: "Boosts calcium absorption",
      detail:
        "Vitamin D stimulates calcium-binding proteins in the intestine, " <>
          "making this a classic synergistic pair.",
      source: "EFSA NDA Panel, 2015"
    },
    %{
      id: :fat_required_for_vitamin_a,
      type: :requires,
      nutrient_a: "Vitamin A",
      nutrient_b: "Total Fat",
      badge: :tip,
      label: "Needs fat to absorb",
      detail:
        "Vitamin A is fat-soluble. Pair with olive oil, avocado, or nuts " <>
          "to absorb it properly.",
      source: "NIH ODS – Vitamin A fact sheet"
    },
    %{
      id: :fat_required_for_vitamin_d,
      type: :requires,
      nutrient_a: "Vitamin D",
      nutrient_b: "Total Fat",
      badge: :tip,
      label: "Needs fat to absorb",
      detail:
        "Vitamin D is fat-soluble. A fat source in the same meal " <>
          "significantly improves absorption.",
      source: "NIH ODS – Vitamin D fact sheet"
    },
    %{
      id: :fat_required_for_vitamin_e,
      type: :requires,
      nutrient_a: "Vitamin E",
      nutrient_b: "Total Fat",
      badge: :tip,
      label: "Needs fat to absorb",
      detail:
        "Vitamin E is fat-soluble. Combine with a dietary fat source " <>
          "to maximise uptake.",
      source: "NIH ODS – Vitamin E fact sheet"
    },
    %{
      id: :fat_required_for_vitamin_k,
      type: :requires,
      nutrient_a: "Vitamin K",
      nutrient_b: "Total Fat",
      badge: :tip,
      label: "Needs fat to absorb",
      detail:
        "Vitamin K is fat-soluble. A drizzle of oil with leafy greens " <>
          "makes a meaningful difference.",
      source: "NIH ODS – Vitamin K fact sheet"
    },
    %{
      id: :magnesium_enhances_vitamin_d,
      type: :enhances,
      nutrient_a: "Vitamin D",
      nutrient_b: "Magnesium",
      badge: :positive,
      label: "Supports vitamin D activation",
      detail:
        "Magnesium is required to convert vitamin D into its active form. " <>
          "Deficiency in magnesium limits the benefit of vitamin D.",
      source: "Uwitonze & Razzaque, 2018 – J Am Osteopath Assoc"
    },
    %{
      id: :vitamin_c_enhances_folate,
      type: :enhances,
      nutrient_a: "Folate (Vitamin B9)",
      nutrient_b: "Vitamin C",
      badge: :positive,
      label: "Protects folate",
      detail:
        "Vitamin C protects folate from oxidative degradation during " <>
          "digestion, preserving more of it for absorption.",
      source: "Linus Pauling Institute – Folate"
    }
  ]

  @doc """
  Returns all nutrient interactions that apply to the given ingredient IDs.

  Each returned map contains the rule fields plus:
  - `:source_ingredient_ids` — IDs of ingredients providing nutrient_a
  - `:interacting_ingredient_ids` — IDs of ingredients providing nutrient_b
    (absent on :requires rules where nutrient_b is missing)
  - `:missing_nutrient` — set on :requires rules where nutrient_b is absent,
    indicating the ingredient to add
  """
  def interactions_for_ingredients(ingredient_ids) when ingredient_ids == [], do: []

  def interactions_for_ingredients(ingredient_ids) do
    nutrient_map = load_nutrient_map(ingredient_ids)
    significant = classify_significant_nutrients(nutrient_map)
    check_rules(@rules, significant)
  end

  @doc "Exposes the full rule list for UI display (e.g. a legend or help page)."
  def rules, do: @rules

  # ── Private ────────────────────────────────────────────────────────────────

  defp load_nutrient_map(ingredient_ids) do
    rows =
      Repo.all(
        from in_n in IngredientNutrient,
          join: n in Nutrient,
          on: in_n.nutrient_id == n.id,
          where: in_n.ingredient_id in ^ingredient_ids,
          select: {in_n.ingredient_id, n.name, in_n.amount}
      )

    Enum.reduce(rows, %{}, fn {ing_id, name, amount}, acc ->
      canonical = NutrientNameNormalizer.normalize(name)
      Map.update(acc, ing_id, [{canonical, amount || 0.0}], &[{canonical, amount || 0.0} | &1])
    end)
  end

  defp classify_significant_nutrients(nutrient_map) do
    Map.new(nutrient_map, fn {ing_id, nutrients} ->
      significant =
        nutrients
        |> Enum.filter(fn {name, amount} ->
          case Map.get(@thresholds, name) do
            nil -> false
            threshold -> amount >= threshold
          end
        end)
        |> Enum.map(&elem(&1, 0))
        |> MapSet.new()

      {ing_id, significant}
    end)
  end

  defp check_rules(rules, significant) do
    ingredient_ids = Map.keys(significant)

    Enum.flat_map(rules, fn rule ->
      providers_a = Enum.filter(ingredient_ids, &has_nutrient?(significant, &1, rule.nutrient_a))
      providers_b = Enum.filter(ingredient_ids, &has_nutrient?(significant, &1, rule.nutrient_b))

      case {providers_a, providers_b} do
        {[], _} ->
          []

        {a, []} when rule.type == :requires ->
          [Map.merge(rule, %{source_ingredient_ids: a, missing_nutrient: rule.nutrient_b})]

        {_, []} ->
          []

        {a, b} ->
          [Map.merge(rule, %{source_ingredient_ids: a, interacting_ingredient_ids: b})]
      end
    end)
  end

  defp has_nutrient?(significant, ingredient_id, nutrient_name) do
    significant
    |> Map.get(ingredient_id, MapSet.new())
    |> MapSet.member?(nutrient_name)
  end
end
