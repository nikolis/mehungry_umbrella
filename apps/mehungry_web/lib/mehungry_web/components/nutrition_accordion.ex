defmodule MehungryWeb.NutritionAccordion do
  use Phoenix.Component
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
      |> resolve_fatty_acid_names()

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
              No nutrition data available
            </div>
          <% else %>
            <.accordion items={@nutrient_list} accordion_id="nutrition-accordion" />
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # Resolve fatty-acid notation to common names live, at render time, so the
  # stored hierarchy keeps the raw USDA notation (e.g. "MUFA 16:1") and matcher
  # improvements apply to already-saved recipes without recalculation. Walks the
  # whole nutrient tree; non-fatty-acid nodes are left untouched.
  defp resolve_fatty_acid_names(nodes) when is_list(nodes) do
    Enum.map(nodes, &resolve_fatty_acid_names/1)
  end

  defp resolve_fatty_acid_names(node) when is_map(node) do
    # Prefer the raw notation preserved in `original_name`; fall back to `name`
    # (which may already be a baked display string from older data — the matcher
    # still extracts the lipid number from it).
    raw = get_value(node, :original_name) || get_value(node, :name)

    node =
      if is_binary(raw) and FattyAcidMatcher.fatty_acid?(raw) do
        put_name(node, FattyAcidMatcher.display_name(raw))
      else
        node
      end

    case get_value(node, :children) do
      children when is_list(children) and children != [] ->
        put_children(node, Enum.map(children, &resolve_fatty_acid_names/1))

      _ ->
        node
    end
  end

  defp resolve_fatty_acid_names(other), do: other

  # Write back to whichever key representation the (JSON-decoded) node uses.
  defp put_name(node, value) do
    if Map.has_key?(node, "name"), do: Map.put(node, "name", value), else: Map.put(node, :name, value)
  end

  defp put_children(node, value) do
    if Map.has_key?(node, "children"),
      do: Map.put(node, "children", value),
      else: Map.put(node, :children, value)
  end
end
