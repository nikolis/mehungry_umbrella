defmodule MehungryWeb.NutritionAccordion do
  use Phoenix.Component
  import MehungryWeb.AccordionComponent

  # Helper to safely get values for sorting
  defp get_value(map, key) when is_tuple(map) do
    {_, inner_map} = map
    get_value(inner_map, key)
  end

  defp get_value(map, key) when is_map(map) do
    get_value_specific(map, key) || get_value_specific(map, Atom.to_string(key))
  end

  defp get_value(_, _), do: nil

  defp get_value_specific(map, key) when is_atom(key) do
    map[key] || map[to_string(key)]
  end

  defp get_value_specific(map, key) when is_binary(key) do
    map[key] || map[String.to_atom(key)]
  end

  defp get_value_specific(_, _), do: nil

  attr :nutrients, :map, required: true
  attr :title, :string, default: "Nutrition Facts"
  attr :max_height, :string, default: "500px"
  attr :show_title, :boolean, default: true

  def nutrition_accordion(assigns) do
    # Convert map to sorted list with custom priority
    nutrient_list =
      assigns.nutrients
      |> Enum.map(fn {_key, value} -> value end)
      |> Enum.sort_by(fn item ->
        name =
          case get_value(item, :name) do
            n when is_binary(n) -> n
            n when is_atom(n) -> Atom.to_string(n)
            _ -> ""
          end

        priority =
          case name do
            "Energy" -> 1
            "Protein" -> 2
            "Total Fat" -> 3
            "Carbohydrates" -> 4
            "Vitamins" -> 5
            "Fiber" -> 6
            "Total Sugars" -> 7
            "Minerals" -> 8
            _ -> 99
          end

        {priority, name}
      end)

    assigns = assign(assigns, nutrient_list: nutrient_list)

    ~H"""
    <div
      class="w-full max-w-full overflow-hidden  rounded-xl shadow-sm max-h-72 px-4"
    >
      
    <!-- Scrollable container with proper overflow containment -->
      <div
        class=" overflow-y-auto custom-scrollbar  overflow-x-hidden  "
      >
        <%= if Enum.empty?(@nutrient_list) do %>
          <div class="text-center  text-white text-sm">
            No nutrition data available
          </div>
        <% else %>
          <.accordion items={@nutrient_list} accordion_id="nutrition-accordion" />
        <% end %>
      </div>
    </div>
    """
  end
end
