defmodule MehungryWeb.NutritionAccordion do
  use Phoenix.Component
  use Gettext, backend: MehungryWeb.Gettext
  import MehungryWeb.AccordionComponent

  alias Mehungry.Food.Nutrition.FattyAcidMatcher

  # Helper to safely get values for sorting
  defp get_value(map, key) when is_tuple(map) and tuple_size(map) == 2 do
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
  attr :locale, :string, default: "en"
  # Must be unique per rendered accordion on the page: the accordion is a
  # pure-CSS checkbox hack, so `<label for={id}>` toggles the *first* matching id
  # in the DOM. Sharing one id across several accordions (e.g. a nutrition facts
  # card per day on the calendar) makes every card toggle the first one's rows.
  attr :accordion_id, :string, default: "nutrition-accordion"

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
      |> FattyAcidMatcher.resolve_names()
      # Localize display names last, so fatty-acid nodes are keyed on their final
      # English display string (resolve_names overwrites raw "MUFA 16:1" names).
      |> MehungryWeb.NutrientLabels.translate_names(assigns.locale)

    assigns = assign(assigns, nutrient_list: nutrient_list)

    ~H"""
    <div class="w-full">
      <div :if={@show_title} class="px-4 pt-4 pb-2">
        <h3 class="font-display font-medium text-parchment">{@title}</h3>
      </div>
      <div class="w-full  custom-scrollbar overflow-y-auto max-w-full overflow-hidden  max-h-72 px-4 pb-4">
        <!-- Scrollable container with proper overflow containment -->
        <div class="  overflow-x-hidden  ">
          <%= if Enum.empty?(@nutrient_list) do %>
            <div class="text-center  text-parchment-dim text-sm">
              {gettext("No nutrition data available")}
            </div>
          <% else %>
            <.accordion items={@nutrient_list} accordion_id={@accordion_id} />
          <% end %>
        </div>
      </div>
    </div>
    """
  end

end
