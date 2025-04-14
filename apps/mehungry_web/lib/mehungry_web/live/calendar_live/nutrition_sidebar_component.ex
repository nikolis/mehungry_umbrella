defmodule MehungryWeb.CalendarLive.NutritionSidebarComponent do
  
  use Phoenix.Component

  def nutrition_sidebar(assigns) do
    ~H"""
    <div>
      <h2 class="text-lg font-bold mb-2">Nutrition Summary</h2>
      <%= for {metric, value} <- @nutrition_data do %>
        <div class="mb-2">
          <p class="text-sm text-gray-600"><%= metric %>: <%= value %></p>
          <div class="w-full bg-gray-100 h-2 rounded">
            <div class="bg-blue-500 h-2 rounded" style={"width: #{value}%"}></div>
          </div>
        </div>
      <% end %>

      <%= if @warnings != [] do %>
        <div class="mt-4 bg-yellow-100 text-yellow-800 p-3 rounded">
          <h3 class="font-semibold">⚠️ Warnings</h3>
          <ul class="list-disc list-inside text-sm">
            <%= for w <- @warnings do %>
              <li><%= w %></li>
            <% end %>
          </ul>
        </div>
      <% end %>
    </div>
    """
  end
end
