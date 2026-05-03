defmodule MehungryWeb.AccordionComponent do
  use Phoenix.Component

  # ============================================================================
  # get_value Helpers - Safely access both atom and string keys
  # ============================================================================

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

  # ============================================================================
  # Component Attributes
  # ============================================================================

  attr :items, :list, required: true
  attr :level, :integer, default: 1
  attr :accordion_id, :string, required: true

  def accordion(assigns) do
    ~H"""
    <div class="w-full">
      <%= for {item, index} <- Enum.with_index(@items) do %>
        <.accordion_item 
          item={item} 
          level={@level} 
          index={index}
          accordion_id={@accordion_id}
        />
      <% end %>
    </div>
    """
  end

  attr :item, :map, required: true
  attr :level, :integer, required: true
  attr :index, :integer, required: true
  attr :accordion_id, :string, required: true

  defp accordion_item(assigns) do
    # Use get_value to safely access both atom and string keys
    children_list = case get_value(assigns.item, :children) do
      children when is_list(children) -> children
      _ -> []
    end
    
    has_children = length(children_list) > 0
    
    # Create a unique ID for this accordion item
    item_id = "#{get_value(assigns, :accordion_id)}-l#{get_value(assigns, :level)}-i#{get_value(assigns, :index)}"
    
    # Safely extract values using get_value
    amount = case get_value(assigns.item, :amount) do
      a when is_number(a) -> a
      _ -> 0.0
    end
    
    unit = case get_value(assigns.item, :measurement_unit) do
      u when is_binary(u) -> u
      _ -> ""
    end
    
    name = case get_value(assigns.item, :name) do
      n when is_binary(n) -> n
      n when is_atom(n) -> Atom.to_string(n)
      _ -> "Unknown"
    end
    
    # Determine indentation based on level (Tailwind classes)
    indent_class = case assigns.level do
      1 -> ""  # No indent for level 1
      2 -> "ml-4"
      3 -> "ml-8"
      4 -> "ml-12"
      _ -> "ml-4"
    end
    
    # Background color based on level
    bg_class = case assigns.level do
      1 -> "bg-white"
      2 -> "bg-gray-50"
      3 -> "bg-gray-50/80"
      _ -> "bg-white"
    end
    
    # Left border for nested items
    border_class = if assigns.level > 1 do
      "border-l-2 border-gray-200"
    else
      ""
    end
    
    assigns = assign(assigns, 
      has_children: has_children,
      item_id: item_id,
      amount: amount,
      unit: unit,
      name: name,
      children_list: children_list,
      indent_class: indent_class,
      bg_class: bg_class,
      border_class: border_class
    )
    
    ~H"""
    <div class={"border-b border-gray-100 #{@indent_class} #{@border_class}"}>
      <%= if @has_children do %>
        <!-- Hidden checkbox for the accordion hack -->
        <input 
          type="checkbox" 
          id={@item_id} 
          class="hidden peer" 
        />
        
        <!-- Clickable label that toggles the checkbox -->
        <label 
          for={@item_id} 
          class={[
            "flex justify-between items-center w-full py-3 px-4 cursor-pointer transition-colors",
            @bg_class,
            "hover:bg-gray-100"
          ]}
        >
          <div class="flex-1 text-left">
            <div class={[
              "text-gray-900",
              @level == 1 && "font-semibold text-base",
              @level == 2 && "font-medium text-sm",
              @level >= 3 && "font-normal text-sm"
            ]}>
              <%= @name %>
            </div>
            <div class="text-xs text-gray-500 mt-0.5">
              <%= @amount %> <%= @unit %>
            </div>
          </div>
          <svg class={[
            "w-5 h-5 text-gray-400 transition-transform duration-200 flex-shrink-0",
            "peer-checked:rotate-180"
          ]} fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
          </svg>
        </label>
        
        <!-- Content that expands/collapses based on checkbox state -->
        <div class="hidden peer-checked:block bg-gray-50 border-t border-gray-100">
          <div class="py-1">
            <.accordion 
              items={@children_list} 
              level={@level + 1}
              accordion_id={@item_id}
            />
          </div>
        </div>
      <% else %>
        <!-- No children - just display the item -->
        <div class={[
          "flex justify-between items-center w-full py-3 px-4",
          @bg_class
        ]}>
          <div class="flex-1 text-left">
            <div class={[
              "text-gray-900",
              @level == 1 && "font-semibold text-base",
              @level == 2 && "font-medium text-sm",
              @level >= 3 && "font-normal text-sm"
            ]}>
              <%= @name %>
            </div>
            <div class="text-xs text-gray-500 mt-0.5">
              <%= @amount %> <%= @unit %>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
