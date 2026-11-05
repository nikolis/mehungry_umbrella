defmodule MehungryWeb.ShoppingBasketLive.Components do
  use Phoenix.Component
  use MehungryWeb, :verified_routes
  use Gettext, backend: MehungryWeb.Gettext

  alias Phoenix.LiveView.JS
  alias Mehungry.Inventory.{BasketItem, BasketIngredient}
  alias Mehungry.PublishedPlans.GroceryAisle

  # ────────────────────────────────────────────────────────────────────────
  # Sidebar: the list of shopping lists
  # ────────────────────────────────────────────────────────────────────────

  attr :shopping_baskets, :list, required: true
  attr :shopping_basket, :any, required: true

  def render_basket_titles(assigns) do
    ~H"""
    <ul class="titles_list" id="basket-titles">
      <%= for basket <- @shopping_baskets do %>
        <div
          class={[
            "p-4 hover:bg-black/20 transition cursor-pointer",
            @shopping_basket && @shopping_basket.id == basket.id &&
              "bg-black/20 border-l-4 border-l-paprika"
          ]}
          phx-click="select_shopping_basket"
          phx-value-id={basket.id}
        >
          <div class="flex justify-between items-start gap-2">
            <div class="flex-1 min-w-0">
              <div class="flex items-center gap-2">
                <svg
                  class="w-4 h-4 text-parchment-dim flex-shrink-0"
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
                <h3 class="font-display font-medium text-parchment truncate">{basket.title}</h3>
              </div>

              <% {done, total} = progress(basket) %>
              <div class="flex items-center gap-3 mt-1 text-xs text-parchment-dim">
                <span>
                  <span class="font-bold text-basil [font-variant-numeric:tabular-nums]">
                    {total}
                  </span>
                  {ngettext("item", "items", total)}
                </span>
                <%= if date_range(basket) do %>
                  <span class="px-1.5 py-0.5 rounded bg-basil/10 text-basil [font-variant-numeric:tabular-nums]">
                    {date_range(basket)}
                  </span>
                <% end %>
              </div>

              <%= if total > 0 do %>
                <div class="mt-2 h-1 w-full rounded-full bg-ink-panel2 overflow-hidden">
                  <div
                    class="h-full bg-basil transition-all"
                    style={"width: #{progress_pct(done, total)}%"}
                  >
                  </div>
                </div>
              <% end %>
            </div>

            <div class="flex gap-1 flex-shrink-0">
              <.link
                patch={~p"/basket/import_items/#{basket.id}"}
                class="p-1.5 text-parchment-dim hover:text-parchment transition"
                title={gettext("Import from a calendar week")}
                phx-click={JS.push("select_shopping_basket")}
                phx-value-id={basket.id}
              >
                <img class="w-5 h-5 mx-auto" src="/images/calendar.svg" alt={gettext("Calendar")} />
              </.link>

              <button
                phx-click="edit_basket"
                phx-value-id={basket.id}
                class="p-1.5 text-parchment-dim hover:text-parchment transition"
                title={gettext("Rename list")}
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
                data-confirm={gettext("Delete “%{title}” and all its items?", title: basket.title)}
                class="p-1.5 text-red-500/70 hover:text-red-400 transition"
                title={gettext("Delete list")}
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

  # ────────────────────────────────────────────────────────────────────────
  # Main panel: the active list's items, grouped by grocery aisle
  # ────────────────────────────────────────────────────────────────────────

  attr :shopping_basket, :any, required: true
  attr :current_language, :string, default: "en"
  attr :editing_item, :any, default: nil

  def render_basket_items(assigns) do
    ~H"""
    <div class="flex-1">
      <div class="bg-ink-panel rounded-xl border border-ink-panel2 overflow-hidden">
        <%= if is_nil(@shopping_basket.id) do %>
          <.first_run_cta />
        <% else %>
          <% {done, total} = progress(@shopping_basket) %>
          <!-- Active list header -->
          <div class="p-5 border-b border-ink-panel2">
            <div class="flex justify-between items-start gap-3">
              <div class="min-w-0">
                <h2 class="text-xl font-display font-medium text-parchment truncate">
                  {@shopping_basket.title}
                </h2>
                <p class="text-parchment-dim text-sm mt-1">
                  <span class="font-bold text-basil [font-variant-numeric:tabular-nums]">
                    {total - done}
                  </span>
                  {gettext("to buy")}
                  <span class="text-parchment-dim/60">·</span>
                  <span class="[font-variant-numeric:tabular-nums]">{total}</span>
                  {ngettext("item", "items", total)}
                </p>
              </div>
              <div class="flex gap-2 flex-shrink-0">
                <.link
                  patch={~p"/basket/import_items/#{@shopping_basket.id}"}
                  class="p-2 rounded-lg text-parchment-dim hover:text-parchment transition"
                  title={gettext("Import from a calendar week")}
                >
                  <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"
                    />
                  </svg>
                </.link>
                <button
                  phx-click="open_add_item_modal"
                  class="inline-flex items-center gap-1.5 px-3 py-2 rounded-lg bg-paprika hover:bg-paprika-soft text-ink font-bold transition"
                >
                  <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M12 4v16m8-8H4"
                    />
                  </svg>
                  <span class="hidden sm:inline">{gettext("Add item")}</span>
                </button>
              </div>
            </div>

            <%= if total > 0 do %>
              <div class="mt-3 h-1.5 w-full rounded-full bg-ink-panel2 overflow-hidden">
                <div
                  class="h-full bg-basil transition-all"
                  style={"width: #{progress_pct(done, total)}%"}
                >
                </div>
              </div>
            <% end %>
          </div>

          <!-- Items, grouped by aisle -->
          <div class="max-h-[60vh] overflow-y-auto">
            <%= if total == 0 do %>
              <.empty_list />
            <% else %>
              <%= for {label, entries} <- grouped_entries(@shopping_basket) do %>
                <div class="px-5 pt-4 pb-1">
                  <h3 class="text-xs uppercase tracking-wide text-parchment-dim font-medium">
                    {aisle_label(label)}
                    <span class="text-parchment-dim/60">({length(entries)})</span>
                  </h3>
                </div>
                <div class="divide-y divide-ink-panel2">
                  <%= for item <- entries do %>
                    <.item_row
                      item={item}
                      current_language={@current_language}
                      editing={same_entry?(@editing_item, item)}
                    />
                  <% end %>
                </div>
              <% end %>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # ────────────────────────────────────────────────────────────────────────
  # One item row (view mode + inline edit mode)
  # ────────────────────────────────────────────────────────────────────────

  attr :item, :any, required: true
  attr :current_language, :string, required: true
  attr :editing, :boolean, default: false

  defp item_row(assigns) do
    ~H"""
    <%= if @editing do %>
      <form phx-submit="update_item" class="flex items-center gap-3 p-4 bg-black/20">
        <input type="hidden" name="item_id" value={@item.id} />
        <input type="hidden" name="item_type" value={entry_type(@item)} />
        <%= if match?(%BasketItem{}, @item) do %>
          <input
            type="text"
            name="name"
            value={@item.name}
            class="flex-1 px-3 py-1.5 bg-black/20 border border-ink-panel2 rounded-lg text-parchment text-sm"
          />
        <% else %>
          <span class="flex-1 text-parchment text-sm">{ingredient_name(@item, @current_language)}</span>
        <% end %>
        <input
          type="number"
          name="quantity"
          value={@item.quantity}
          step="0.25"
          min="0"
          class="w-20 px-2 py-1.5 bg-black/20 border border-ink-panel2 rounded-lg text-parchment text-sm [font-variant-numeric:tabular-nums]"
        />
        <button
          type="submit"
          class="px-2.5 py-1.5 rounded-lg bg-paprika hover:bg-paprika-soft text-ink text-sm font-bold transition"
        >
          {gettext("Save")}
        </button>
        <button
          type="button"
          phx-click="cancel_edit_item"
          class="px-2 py-1.5 text-parchment-dim hover:text-parchment text-sm transition"
        >
          {gettext("Cancel")}
        </button>
      </form>
    <% else %>
      <div class="flex items-center gap-4 p-4 hover:bg-black/20 transition group">
        <button
          phx-click="toggle_basket"
          phx-value-id={@item.id}
          phx-value-type={entry_type(@item)}
          aria-label={gettext("Toggle acquired")}
          class={[
            "w-6 h-6 rounded border-2 flex-shrink-0 transition flex items-center justify-center",
            if(@item.in_storage,
              do: "bg-paprika border-paprika hover:border-paprika-soft",
              else: "border-ink-panel2 hover:border-paprika-soft"
            )
          ]}
        >
          <%= if @item.in_storage do %>
            <svg class="w-4 h-4 text-ink" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="3" d="M5 13l4 4L19 7" />
            </svg>
          <% end %>
        </button>

        <div class="flex-1 min-w-0">
          <div class="flex items-center gap-2">
            <span class={[
              "text-parchment truncate",
              @item.in_storage && "line-through text-parchment-dim"
            ]}>
              {ingredient_name(@item, @current_language)}
            </span>
            <.provenance_chip item={@item} />
          </div>
          <div class="text-xs text-parchment-dim mt-0.5">
            <span class="font-bold text-basil [font-variant-numeric:tabular-nums]">
              {format_quantity(@item.quantity)}
            </span>
            {entry_unit(@item)}
          </div>
        </div>

        <div class="flex gap-1 opacity-0 group-hover:opacity-100 focus-within:opacity-100 transition">
          <button
            phx-click="edit_item"
            phx-value-id={@item.id}
            phx-value-type={entry_type(@item)}
            aria-label={gettext("Edit item")}
            class="p-1.5 text-parchment-dim hover:text-parchment"
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
            phx-click="delete_item"
            phx-value-id={@item.id}
            phx-value-type={entry_type(@item)}
            data-confirm={gettext("Remove this item?")}
            aria-label={gettext("Remove item")}
            class="p-1.5 text-red-500/70 hover:text-red-400"
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
    <% end %>
    """
  end

  attr :item, :any, required: true

  defp provenance_chip(assigns) do
    ~H"""
    <%= case provenance(@item) do %>
      <% :plan -> %>
        <span class="flex-shrink-0 px-1.5 py-0.5 rounded text-[10px] uppercase tracking-wide bg-basil/10 text-basil">
          {gettext("From plan")}
        </span>
      <% :manual -> %>
        <span class="flex-shrink-0 px-1.5 py-0.5 rounded text-[10px] uppercase tracking-wide bg-paprika/10 text-paprika-soft">
          {gettext("Added")}
        </span>
    <% end %>
    """
  end

  defp empty_list(assigns) do
    ~H"""
    <div class="text-center py-12">
      <svg
        class="w-16 h-16 mx-auto text-parchment-dim mb-4"
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
      <p class="text-parchment-dim">{gettext("No items in this list yet")}</p>
      <button
        class="mt-4 text-paprika-soft hover:text-paprika text-sm transition"
        phx-click="open_add_item_modal"
      >
        {gettext("+ Add your first item")}
      </button>
    </div>
    """
  end

  defp first_run_cta(assigns) do
    ~H"""
    <div class="text-center py-16 px-6">
      <svg
        class="w-16 h-16 mx-auto text-parchment-dim mb-4"
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
      <h2 class="font-display font-medium text-parchment text-lg">
        {gettext("No shopping lists yet")}
      </h2>
      <p class="text-parchment-dim mt-1 max-w-sm mx-auto">
        {gettext("Create a list to start adding groceries, or build one from a week on your calendar.")}
      </p>
      <button
        phx-click="new_basket_form"
        class="mt-5 inline-flex items-center gap-1.5 px-4 py-2 rounded-lg bg-paprika hover:bg-paprika-soft text-ink font-bold transition"
      >
        <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
        </svg>
        {gettext("Create your first list")}
      </button>
    </div>
    """
  end

  # ────────────────────────────────────────────────────────────────────────
  # Private helpers
  # ────────────────────────────────────────────────────────────────────────

  # Groups the basket's entries into `[{aisle_label, entries}]` in canonical
  # shop-route order (empty aisles dropped), acquired items sinking within each
  # group. Reuses `GroceryAisle` so it matches the published-plan grocery list.
  defp grouped_entries(basket) do
    by_key =
      (basket.basket_ingredients ++ basket.basket_items)
      |> Enum.group_by(&aisle_key/1)

    for {key, label} <- GroceryAisle.ordered(),
        entries = Map.get(by_key, key, []),
        entries != [] do
      {label, Enum.sort_by(entries, & &1.in_storage)}
    end
  end

  defp aisle_key(%BasketIngredient{ingredient: %{category: %{name: name}}}) when is_binary(name),
    do: GroceryAisle.classify(name)

  defp aisle_key(_), do: "other"

  # The aisle labels from GroceryAisle.ordered/0 are a small fixed English set;
  # map each to a static gettext msgid so the extractor can see them.
  defp aisle_label("Produce"), do: gettext("Produce")
  defp aisle_label("Meat & Seafood"), do: gettext("Meat & Seafood")
  defp aisle_label("Dairy & Eggs"), do: gettext("Dairy & Eggs")
  defp aisle_label("Bakery & Grains"), do: gettext("Bakery & Grains")
  defp aisle_label("Pantry"), do: gettext("Pantry")
  defp aisle_label("Spices & Seasonings"), do: gettext("Spices & Seasonings")
  defp aisle_label("Beverages"), do: gettext("Beverages")
  defp aisle_label("Other"), do: gettext("Other")
  defp aisle_label(other), do: other

  defp entry_type(%BasketIngredient{}), do: "ingredient"
  defp entry_type(%BasketItem{}), do: "item"

  defp provenance(%BasketIngredient{}), do: :plan
  defp provenance(%BasketItem{}), do: :manual

  defp entry_unit(item) do
    cond do
      match?(%{measurement_unit: %{name: _}}, item) -> item.measurement_unit.name
      not is_nil(Map.get(item, :description)) -> item.description
      true -> nil
    end
  end

  defp same_entry?(nil, _item), do: false

  defp same_entry?(editing, item),
    do: editing.__struct__ == item.__struct__ and editing.id == item.id

  defp progress(basket) do
    entries = basket.basket_ingredients ++ basket.basket_items
    {Enum.count(entries, & &1.in_storage), length(entries)}
  end

  defp progress_pct(_done, 0), do: 0
  defp progress_pct(done, total), do: round(done / total * 100)

  defp date_range(%{start_dt: %NaiveDateTime{} = s, end_dt: %NaiveDateTime{} = e}) do
    "#{Calendar.strftime(s, "%b %-d")} – #{Calendar.strftime(e, "%b %-d")}"
  end

  defp date_range(_), do: nil

  defp format_quantity(q) when is_float(q) do
    if q == Float.round(q), do: trunc(q), else: Float.round(q, 2)
  end

  defp format_quantity(q), do: q

  # Localized ingredient name: translate via the preloaded `ingredient_translation`
  # for non-English locales; plain `name` (or the free-text item name) otherwise.
  defp ingredient_name(item, language) do
    case Map.get(item, :ingredient) do
      %{ingredient_translation: translations, name: name} ->
        translate_ingredient(name, translations, language)

      _ ->
        item.name
    end
  end

  defp translate_ingredient(name, _translations, language) when language in [nil, "en", "En"],
    do: name

  defp translate_ingredient(name, translations, language) do
    case Enum.find(translations, &(&1.language_name == language)) do
      %{name: translated} -> translated
      _ -> name
    end
  end
end
