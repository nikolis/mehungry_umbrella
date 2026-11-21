defmodule Mehungry.Food.SpeciesNutritionSummary do
  @moduledoc """
  The per-100g nutrition *presentation* of a food species' ingredient — the one
  implementation shared by the web species page (`MehungryWeb.SpeciesDetailLive.Index`)
  and the mobile API (`GET /api/v1/species/:slug/nutrition`), so both surfaces show
  the same headline macros and the same deterministic summary sentences.

  Everything here is pure: it reads an ingredient's preloaded
  `ingredient_nutrients: [nutrient: :measurement_unit]` and/or the string-keyed
  hierarchical nutrient tree from
  `Mehungry.Food.NutrientCalculation.ingredient_nutrient_tree/2`.
  """

  alias Mehungry.Food.NutrientCalculation

  @top_nutrient_names [
    "Energy",
    "Protein",
    "Total lipid (fat)",
    "Carbohydrate, by difference",
    "Fiber, total dietary"
  ]

  @display_labels %{
    "Energy" => "Calories",
    "Protein" => "Protein",
    "Total lipid (fat)" => "Fat",
    "Carbohydrate, by difference" => "Carbs",
    "Fiber, total dietary" => "Fiber"
  }

  # ── Ingredient selection ──────────────────────────────────────────────────

  @doc "A species' curated ingredients (USDA foods), name-sorted — the picker order."
  def species_ingredients(%{foundemental_foods: foods}) when is_list(foods) do
    foods
    |> Enum.map(& &1.ingredient)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.name)
  end

  def species_ingredients(_), do: []

  @doc """
  The ingredient shown first: a Foundation-class one (most complete nutrient data),
  else the first of the list. `nil` for an empty list.
  """
  def default_ingredient([]), do: nil

  def default_ingredient(ingredients) do
    Enum.find(ingredients, &(&1.food_class == "Foundation")) || hd(ingredients)
  end

  # ── Headline macros ───────────────────────────────────────────────────────

  @doc """
  The headline macro cards — `[%{label:, amount:, unit:}]` for Calories / Protein /
  Fat / Carbs / Fiber (those present), `unit` being the raw measurement-unit name
  (`"kilocalorie"`, `"gram"`; compact it with `macro_unit/1`).
  """
  def top_nutrients(ingredient_nutrients) do
    # USDA ships up to four "Energy*" rows per ingredient (kcal, kJ, Atwater
    # General, Atwater Specific). A naive Map.new keyed on nutrient name lets the
    # last one win — often the kJ row — so the "Calories" card, meta description,
    # and JSON-LD description reported the kJ value mislabeled as kcal (≈4.17×
    # too high). Collapse the energy rows to the single kcal entry the nutrient
    # tree already uses, then fold its (possibly Atwater-suffixed) name back to
    # the bare "Energy" key so @top_nutrient_names resolves it.
    by_name =
      ingredient_nutrients
      |> NutrientCalculation.filter_energy_duplicates()
      |> Map.new(&{top_nutrient_key(&1.nutrient.name), &1})

    @top_nutrient_names
    |> Enum.flat_map(fn name ->
      case Map.get(by_name, name) do
        nil ->
          []

        in_ ->
          unit =
            if in_.nutrient.measurement_unit, do: in_.nutrient.measurement_unit.name, else: ""

          [%{label: Map.get(@display_labels, name, name), amount: in_.amount, unit: unit}]
      end
    end)
  end

  # filter_energy_duplicates/1 may hand back the kcal energy row under an
  # Atwater-factor name ("Energy (Atwater Specific Factors)"); normalize any
  # "Energy*" name to the bare "Energy" key the display map/lookup expects.
  defp top_nutrient_key("Energy" <> _), do: "Energy"
  defp top_nutrient_key(name), do: name

  # ── Composition summary ──────────────────────────────────────────────────
  # One short paragraph of deterministic, indexable prose for the selected
  # ingredient. Server-rendered (crawlable); the long-tail nutrient terms
  # (sugar/fat names) are the SEO payload, kept to a sentence or two so the page
  # stays uncluttered.

  @doc "The sugar-makeup / fat-quality sentence(s) for `name`'s nutrient `tree`, or nil."
  def composition_summary(_name, tree) when map_size(tree) == 0, do: nil

  def composition_summary(name, tree) do
    carbs = top_amount(tree, "Carbohydrates")
    fat = top_amount(tree, "Total Fat")

    # The energy/protein/carb/fat macros already headline the stat cards (and the
    # JSON-LD + meta description), so the prose deliberately skips the numeric
    # recap and carries only what the cards can't: the sugar makeup and fat
    # quality — the long-tail terms that are this paragraph's real SEO payload.
    [sugar_sentence(name, tree, carbs), fat_sentence(tree, fat)]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> case do
      [] -> nil
      sentences -> Enum.join(sentences, " ")
    end
  end

  # ── Micronutrient highlights ───────────────────────────────────────────────
  # One crawlable sentence naming the food's notable minerals + vitamins with
  # their real per-100g amounts ("…provides 7.6 mg iron, 508 mg potassium, 15 mg
  # vitamin C per 100 g"). This is the SEO payload for the "<food> iron/potassium/
  # vitamin X content per 100g" query family (already showing GSC impressions) —
  # the full breakdown is in the accordion, but a prose sentence matches how those
  # queries are phrased. Only real, positive values are listed (never fabricated).

  # Display priority for notable micronutrients; anything else sorts after these.
  @micronutrient_priority %{
    "Iron" => 1,
    "Calcium" => 2,
    "Potassium" => 3,
    "Magnesium" => 4,
    "Zinc" => 5,
    "Phosphorus" => 6,
    "Vitamin C" => 7,
    "Vitamin A" => 8,
    "Vitamin D" => 9,
    "Vitamin B-6" => 10,
    "Vitamin B-12" => 11,
    "Folate" => 12,
    "Vitamin E" => 13,
    "Vitamin K" => 14,
    "Niacin" => 15,
    "Thiamin" => 16,
    "Riboflavin" => 17,
    "Manganese" => 18,
    "Copper" => 19,
    "Selenium" => 20,
    "Sodium" => 25
  }

  @doc "The notable-micronutrients sentence for `name`'s nutrient `tree`, or nil."
  def micronutrient_summary(name, tree) do
    micros =
      [top_node(tree, "Minerals"), top_node(tree, "Vitamins")]
      |> Enum.flat_map(&((&1 || %{})["children"] || []))
      |> Enum.flat_map(fn node ->
        amount = node["amount"]
        clean = clean_micronutrient_name(node["name"])

        if is_binary(clean) and is_number(amount) and amount > 0 do
          [{clean, amount, normalize_unit(node["measurement_unit"]), micronutrient_rank(clean)}]
        else
          []
        end
      end)
      |> Enum.sort_by(fn {label, _amt, _unit, rank} -> {rank, label} end)
      |> Enum.take(6)

    case micros do
      [] ->
        nil

      list ->
        phrases =
          Enum.map(list, fn {label, amount, unit, _rank} ->
            unit_suffix = if unit != "", do: " #{unit}", else: ""
            "#{format_amount(amount)}#{unit_suffix} #{micronutrient_phrase(label)}"
          end)

        "Per 100 g, #{name} also provides #{join_and(phrases)}."
    end
  end

  defp micronutrient_rank(label), do: Map.get(@micronutrient_priority, label, 50)

  # "Iron, Fe" → "Iron"; "Potassium, K" → "Potassium"; "Vitamin C, total ascorbic
  # acid" → "Vitamin C"; "Folate (Vitamin B9)" → "Folate". Drops the USDA qualifier
  # tail (comma clause) and any trailing parenthetical.
  defp clean_micronutrient_name(name) when is_binary(name) do
    name
    |> String.split(",", parts: 2)
    |> List.first()
    |> String.replace(~r/\s*\(.*\)\s*/, "")
    |> String.trim()
  end

  defp clean_micronutrient_name(_), do: nil

  # Minerals read naturally lowercased in prose ("iron"); vitamin designators keep
  # their conventional casing ("vitamin C", "vitamin B-6", "folate").
  defp micronutrient_phrase("Vitamin " <> rest), do: "vitamin " <> rest
  defp micronutrient_phrase(label), do: String.downcase(label)

  defp sugar_sentence(name, tree, carbs) do
    carbs_node = top_node(tree, "Carbohydrates")
    sugars = node_amount(find_desc(carbs_node, ["Total Sugars"]))

    cond do
      not (is_number(sugars) and sugars > 0) ->
        nil

      is_number(carbs) and carbs > 0 and sugars / carbs >= 0.8 ->
        "Per 100 g, #{name}'s carbohydrate is almost entirely sugar (#{format_amount(sugars)} g#{leading_sugar_suffix(carbs_node)})."

      true ->
        "Per 100 g, #{name} contains #{format_amount(sugars)} g of total sugars#{leading_sugar_suffix(carbs_node)}."
    end
  end

  @sugar_names ["Fructose", "Glucose", "Galactose", "Sucrose", "Lactose", "Maltose"]

  defp leading_sugar_suffix(carbs_node) do
    carbs_node
    |> collect_nodes()
    |> Enum.filter(fn {n, a} -> n in @sugar_names and a > 0 end)
    |> Enum.sort_by(fn {_n, a} -> -a end)
    |> Enum.take(2)
    |> case do
      [] -> ""
      list -> ", led by " <> join_and(Enum.map(list, fn {n, _a} -> String.downcase(n) end))
    end
  end

  defp fat_sentence(tree, fat) when is_number(fat) and fat >= 1.0 do
    node = top_node(tree, "Total Fat")
    sat = child_amount(node, "Saturated Fat") || 0.0

    unsat =
      (child_amount(node, "Monounsaturated Fat") || 0.0) +
        (child_amount(node, "Polyunsaturated Fat") || 0.0)

    cond do
      unsat > sat and unsat > 0 -> "Its fat is mostly unsaturated."
      sat > unsat and sat > 0 -> "Its fat is mostly saturated."
      true -> nil
    end
  end

  defp fat_sentence(_tree, _fat), do: nil

  # ── String-keyed nutrient-tree accessors ──────────────────────────────────

  @doc "The top-level tree node named `name`, or nil."
  def top_node(tree, name) when is_map(tree), do: Map.get(tree, name)
  def top_node(_tree, _name), do: nil

  @doc "The numeric amount of the top-level node named `name`, or nil."
  def top_amount(tree, name), do: node_amount(top_node(tree, name))

  @doc "The direct child of `node` named `name`, or nil."
  def child_node(node, name) when is_map(node) do
    Enum.find(node["children"] || [], &(&1["name"] == name))
  end

  def child_node(_node, _name), do: nil

  @doc "The numeric amount of `node`'s direct child named `name`, or nil."
  def child_amount(node, name), do: node_amount(child_node(node, name))

  @doc "First descendant (self included) whose name is in `names`, searching children."
  def find_desc(nil, _names), do: nil

  def find_desc(node, names) when is_map(node) do
    if node["name"] in names do
      node
    else
      Enum.find_value(node["children"] || [], &find_desc(&1, names))
    end
  end

  # {name, amount} for this node and every descendant that has a numeric amount.
  defp collect_nodes(nil), do: []

  defp collect_nodes(node) when is_map(node) do
    self_entry =
      case {node["name"], node["amount"]} do
        {n, a} when is_binary(n) and is_number(a) -> [{n, a}]
        _ -> []
      end

    self_entry ++ Enum.flat_map(node["children"] || [], &collect_nodes/1)
  end

  @doc "A node's numeric amount, or nil."
  def node_amount(node) when is_map(node) do
    case node["amount"] do
      a when is_number(a) -> a
      _ -> nil
    end
  end

  def node_amount(_), do: nil

  # ── Formatting ────────────────────────────────────────────────────────────

  @doc "Standard nutrition unit abbreviation (`\"milligram\"` → `\"mg\"`); `\"\"` for nil."
  def normalize_unit("kilocalorie"), do: "kcal"
  def normalize_unit("kcal"), do: "kcal"
  def normalize_unit("gram"), do: "g"
  def normalize_unit("milligram"), do: "mg"
  def normalize_unit("microgram"), do: "µg"
  def normalize_unit(unit) when is_binary(unit), do: unit
  def normalize_unit(_), do: ""

  @doc "Compact unit label for the headline macro cards (`kilocalorie → \"kcal\"`)."
  def macro_unit("kilocalorie"), do: "kcal"
  def macro_unit("gram"), do: "g"
  def macro_unit("milligram"), do: "mg"
  def macro_unit("microgram"), do: "µg"
  def macro_unit(other), do: other

  @doc "`[a, b, c]` → `\"a, b and c\"`."
  def join_and([]), do: ""
  def join_and([only]), do: only

  def join_and(list) do
    {init, [last]} = Enum.split(list, length(list) - 1)
    Enum.join(init, ", ") <> " and " <> last
  end

  @doc "One decimal at ≥ 1, three below (a micronutrient cell); `\"—\"` for nil."
  def format_amount(nil), do: "—"

  def format_amount(amount) when is_float(amount) do
    if amount >= 1 do
      amount |> Float.round(1) |> :erlang.float_to_binary(decimals: 1)
    else
      amount |> Float.round(3) |> :erlang.float_to_binary(decimals: 3)
    end
  end

  def format_amount(amount), do: to_string(amount)
end
