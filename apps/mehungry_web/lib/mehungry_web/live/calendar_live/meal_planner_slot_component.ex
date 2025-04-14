defmodule MehungryWeb.CalendarLive.SlotComponent do
  use Phoenix.LiveComponent

  def render(assigns) do
    ~L"""
    <div class="p-4 border rounded shadow">
      <%= if @meal do %>
        <div class="flex flex-col items-center">
          <img src="<%= @meal.image_url %>" alt="<%= @meal.name %>" class="h-32 w-32 object-cover mb-2"/>
          <p class="font-semibold text-center"><%= @meal.name %></p>
        </div>
      <% else %>
        <button phx-click="add_meal" phx-value-day={@day} phx-value-slot={@meal.type} class="w-full text-center text-blue-500 bg-blue-50 p-2 rounded-md">
          + Add Meal
        </button>
      <% end %>
    </div>
    """
  end
end

