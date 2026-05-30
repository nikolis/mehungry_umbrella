defmodule MehungryWeb.FoodDetailLive.Index do
  use MehungryWeb, :live_view
  alias Mehungry.Food

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

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    case Food.get_ingredient_by_slug(slug) do
      nil ->
        {:ok, push_navigate(socket, to: "/foods")}

      ingredient ->
        top_nutrients = build_top_nutrients(ingredient.ingredient_nutrients)

        nutrients_by_family =
          ingredient.ingredient_nutrients
          |> Enum.sort_by(& &1.nutrient.rank)
          |> Enum.group_by(&(&1.nutrient.family || "Other"))
          |> Enum.sort_by(fn {family, _} -> family_sort_order(family) end)

        {_query, {recipes, _cursor}} = Food.search_recipes_by_ingredient(ingredient.name)
        sample_recipes = Enum.take(recipes, 5)

        interactions = Food.get_interactions_for_ingredients([ingredient.id])

        {:ok,
         socket
         |> assign(:ingredient, ingredient)
         |> assign(:top_nutrients, top_nutrients)
         |> assign(:nutrients_by_family, nutrients_by_family)
         |> assign(:sample_recipes, sample_recipes)
         |> assign(:interactions, interactions)
         |> assign(:page_title, "#{ingredient.name} Nutrition Facts")
         |> assign(:page_description, build_description(ingredient, top_nutrients))}
    end
  end

  defp build_top_nutrients(ingredient_nutrients) do
    by_name = Map.new(ingredient_nutrients, &{&1.nutrient.name, &1})

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

  defp family_sort_order("Proximates"), do: 0
  defp family_sort_order("Lipids"), do: 1
  defp family_sort_order("Minerals"), do: 2
  defp family_sort_order("Vitamins and Other Components"), do: 3
  defp family_sort_order("Amino Acids"), do: 4
  defp family_sort_order(_), do: 5

  defp build_description(ingredient, top_nutrients) do
    macro_str =
      top_nutrients
      |> Enum.map(fn n -> "#{n.label}: #{format_amount(n.amount)}#{n.unit}" end)
      |> Enum.join(", ")

    if macro_str != "" do
      "#{ingredient.name} nutrition facts per 100g — #{macro_str}. Full breakdown of vitamins, minerals, and macronutrients."
    else
      "Complete nutrition facts for #{ingredient.name} — vitamins, minerals, and macronutrient breakdown."
    end
  end

  def format_amount(nil), do: "—"

  def format_amount(amount) when is_float(amount) do
    if amount >= 1 do
      amount |> Float.round(1) |> :erlang.float_to_binary(decimals: 1)
    else
      amount |> Float.round(3) |> :erlang.float_to_binary(decimals: 3)
    end
  end

  def format_amount(amount), do: to_string(amount)

  def ingredient_slug(ingredient) do
    String.replace(ingredient.search_name || "", " ", "-")
  end
end
