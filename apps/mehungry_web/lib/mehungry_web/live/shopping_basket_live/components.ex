defmodule MehungryWeb.ShoppingBasketLive.Components do
  use Phoenix.Component
  use MehungryWeb, :verified_routes

  def get_active_class(basket_1, basket_2) do
    case basket_1.id == basket_2.id do
      true ->
        "active"

      false ->
        ""
    end
  end

  def render_basket_titles(assigns) do
    ~H"""
    <ul class="titles_list overflowx-y-scroll" id="user_id">
      <%= for basket <- @shopping_baskets do %>
        <div
          class={[
            "p-4 hover:bg-slate-700/50 transition cursor-pointer",
            if(@shopping_basket.id == basket.id,
              do: "bg-slate-700/50 border-l-4 border-l-primary-500"
            )
          ]}
          phx-click="select_shopping_basket"
          phx-value-id={basket.id}
        >
          <div class="flex justify-between items-start">
            <div class="flex-1">
              <div class="flex items-center gap-2">
                <svg
                  class="w-4 h-4 text-slate-400"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2"
                  />
                </svg>
                <h3 class="text-white font-medium">{basket.title}</h3>
              </div>
              <div class="flex gap-3 mt-1 text-xs text-slate-400">
                <span>{length(@shopping_basket.basket_ingredients)} items</span>
                <span>{basket.start_dt}</span>
              </div>
            </div>
            <div class="flex gap-1">
              <.link
                patch={~p"/basket/import_items/#{basket.id}"}
                phx-value-id={basket.id}
                class="p-1.5 text-slate-400 hover:text-primary-500 transition"
                phx-click={
                  Phoenix.LiveView.JS.push("select_shopping_basket")
                  |> Phoenix.LiveView.JS.remove_class("active", to: "#basket-side-navbar.active")
                  |> Phoenix.LiveView.JS.add_class("active", to: "#basket-side-navbar:not(.active)")
                }
              >
                <img class="w-5 h-5 mx-auto" src="/images/calendar.svg" />
              </.link>

              <button
                phx-click="edit_basket"
                phx-value-id={basket.id}
                phx-stop-propagation="click"
                class="p-1.5 text-slate-400 hover:text-primary-500 transition"
              >
                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M15.232 5.232l3.536 3.536m-2.036-5.036a2.5 2.5 0 113.536 3.536L6.5 21.036H3v-3.572L16.732 3.732z"
                  />
                </svg>
              </button>
              <button
                phx-click="delete_basket"
                phx-value-id={basket.id}
                phx-stop-propagation="click"
                class="p-1.5 text-slate-400 hover:text-red-400 transition"
              >
                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"
                  />
                </svg>
              </button>
            </div>
          </div>
        </div>
      <% end %>
    </ul>
    """
  end

  def render_basket_items(assigns) do
    ~H"""
    <!-- Main Content - Items -->
    <div class="flex-1">
      <div class="bg-slate-800 rounded-xl border border-slate-700 overflow-hidden">
        <!-- Active List Header -->
        <div class="p-5 border-b border-slate-700">
          <div class="flex justify-between items-start">
            <div>
              <h2 class="text-xl font-bold text-white">
                {@shopping_basket.title}
              </h2>
              <p class="text-slate-400 text-sm mt-1">
                {length(@shopping_basket.basket_ingredients)} items • Last updated today
              </p>
            </div>
            <div class="flex gap-2">
              <!-- Calendar / Meal Planning -->
              <a
                href="/basket/import_items/3"
                class="p-2 rounded-lg bg-slate-700 hover:bg-slate-600 text-slate-300 transition"
              >
                <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"
                  />
                </svg>
              </a>
              <!-- Add Item -->
              <button class="p-2 rounded-lg bg-primary-500 hover:bg-primary-600 text-white transition">
                <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M12 4v16m8-8H4"
                  />
                </svg>
              </button>
            </div>
          </div>
        </div>
        
    <!-- Items List -->
        <div class="divide-y divide-slate-700 max-h-[60vh] overflow-y-auto">
          <%= if Enum.empty?(@shopping_basket.basket_ingredients ) do %>
            <div class="text-center py-12">
              <svg
                class="w-16 h-16 mx-auto text-slate-600 mb-4"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M3 3h2l.4 2M7 13h10l4-8H5.4M7 13L5.4 5M7 13l-1.5 1.5M17 13l1.5 1.5M9 21h6M12 21v-8"
                />
              </svg>
              <p class="text-slate-400">No items in this list</p>
              <button class="mt-4 text-primary-500 hover:text-primary-400 text-sm transition">
                + Add your first item
              </button>
            </div>
          <% else %>
            <%= for item <- @shopping_basket.basket_ingredients do %>
              <div class="flex items-center gap-4 p-4 hover:bg-slate-700/30 transition group">
                <!-- Checkbox -->
                <button
                  phx-click="toggle_basket"
                  phx-value-id={item.id}
                  class={[
                    "w-5 h-5 rounded border-2 flex-shrink-0 transition",
                    if(item.in_storage) do
                      "bg-primary-500 border-primary-500 border-slate-500 hover:border-primary-500"
                    end
                  ]}
                >
                  <%= if item.in_storage do %>
                    <svg
                      class="w-4 h-4 text-white"
                      fill="none"
                      stroke="currentColor"
                      viewBox="0 0 24 24"
                    >
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M5 13l4 4L19 7"
                      />
                    </svg>
                  <% end %>
                </button>
                
    <!-- Item Details -->
                <div class="flex-1">
                  <div class={["text-white", if(item.in_storage, do: "line-through text-slate-500")]}>
                    {item.ingredient.name}
                  </div>
                  <div class="text-xs text-slate-400 mt-0.5">
                    {item.quantity} {item.measurement_unit.name}
                  </div>
                </div>
                
    <!-- Actions -->
                <div class="flex gap-1 opacity-0 group-hover:opacity-100 transition">
                  <button
                    phx-click="edit_item"
                    phx-value-id={item.id}
                    class="p-1.5 text-slate-400 hover:text-primary-500"
                  >
                    <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M15.232 5.232l3.536 3.536m-2.036-5.036a2.5 2.5 0 113.536 3.536L6.5 21.036H3v-3.572L16.732 3.732z"
                      />
                    </svg>
                  </button>
                </div>
              </div>
            <% end %>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  def get_class_for_toggle_button(in_stock) do
    case in_stock do
      true ->
        "checked"

      false ->
        "unchecked"
    end
  end
end
