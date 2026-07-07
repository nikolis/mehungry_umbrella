defmodule MehungryWeb.FoodDetailLive.Index do
  use MehungryWeb, :live_view
  use MehungryWeb.Presence, :user_tracking
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
    maybe_track_user(%{}, socket)

    case Food.get_ingredient_by_slug(slug) do
      nil ->
        {:ok, push_navigate(socket, to: "/foods")}

      ingredient ->
        language = socket.assigns[:current_language] || "en"

        display_name =
          if language == "el" do
            case Food.find_ingredient_translation("el", ingredient.id) do
              [greek_name | _] -> greek_name
              [] -> ingredient.name
            end
          else
            ingredient.name
          end

        top_nutrients= build_top_nutrients(ingredient.ingredient_nutrients)


        {:ok,
         socket
         |> assign(:ingredient, ingredient)
         |> assign(:display_name, display_name)
         |> assign_async(
           [:sample_recipes, :interactions, :top_nutrients, :nutrients_by_family],
           fn ->
             {:ok,
              %{
                sample_recipes: Food.list_sample_recipes_for_ingredient(ingredient.id),
                interactions: Food.get_interactions_for_ingredients([ingredient.id]),
                top_nutrients: build_top_nutrients(ingredient.ingredient_nutrients),
                nutrients_by_family:
                  ingredient.ingredient_nutrients
                  |> Enum.sort_by(& &1.nutrient.rank)
                  |> Enum.group_by(&(&1.nutrient.family || "Other"))
                  |> Enum.sort_by(fn {family, _} -> family_sort_order(family) end)
              }}
           end,
           []
         )
         |> assign(:page_title, "#{display_name} - #{page_title_suffix(language)}")
         |> assign(:page_description, build_description(display_name, top_nutrients))}
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

  defp page_title_suffix("el"), do: "Διατροφικά Στοιχεία"
  defp page_title_suffix(_), do: "Nutrition Facts"

  defp build_description(display_name, top_nutrients) do
    macro_str =
      top_nutrients
      |> Enum.map(fn n -> "#{n.label}: #{format_amount(n.amount)}#{n.unit}" end)
      |> Enum.join(", ")

    if macro_str != "" do
      "#{display_name} nutrition facts per 100g — #{macro_str}. Full breakdown of vitamins, minerals, and macronutrients."
    else
      "Complete nutrition facts for #{display_name} — vitamins, minerals, and macronutrient breakdown."
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
