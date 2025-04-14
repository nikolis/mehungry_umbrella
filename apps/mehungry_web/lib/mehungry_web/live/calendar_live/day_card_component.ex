defmodule MehungryWeb.DayCardComponent do
  use MehungryWeb, :live_component

  def render(assigns) do
    ~H"""
    <div class="bg-gray-50 p-4 rounded-lg shadow-sm">
      <h3 class="font-bold mb-2"><%= @day.date %></h3>
      <%= inspect @day %>
      <%= for meal_type <- [:breakfast, :lunch, :dinner] do %>
        <%= for  meal <- @day.meals  do %>
          <.meal_slot meal={meal} type={meal_type} /> 
          <% end %>
      <% end %>
    </div>
    """
  end

  defp meal_slot(assigns) do
    ~H"""
    <div class="border border-gray-200 rounded p-2 mt-2">
      <p class="text-sm font-medium capitalize"><%= @type %></p>
      <%= if @meal do %>
        <p class="text-xs text-gray-700"><%= @meal.meal %></p>
      <% else %>
        <button class="text-blue-600 text-sm mt-1">+ Add meal</button>
      <% end %>
    </div>
    """
  end
end

