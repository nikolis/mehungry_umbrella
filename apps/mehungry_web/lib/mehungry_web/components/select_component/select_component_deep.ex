defmodule MehungryWeb.SelectComponentDeep do
  use MehungryWeb, :live_component
  import Ecto.Changeset, only: [get_field: 2, change: 2]

  @impl true
  def render(assigns) do
    ~H"""
    <div
      class="h-full relative"
      id={"select-component-#{@unique_id}"}
      data-component-id={@unique_id}
    >
      <!-- Hidden input for form value -->
      <input
        type="hidden"
        name={@form.name <> "[#{@input_variable}]"}
        id={@form.name <> "_#{@input_variable}"}
        value={@selected_id}
      />

      <!-- Trigger Button / Selected Item Display -->
      <div phx-click="open_modal" phx-target={@myself} class="w-full cursor-pointer h-full">
        <%= if @selected_item do %>
          <div class="bg-ink-panel2 border border-[#3A3323] rounded-lg text-parchment px-4 py-2 min-h-10 flex justify-between items-center h-full transition-colors hover:border-paprika">
            <span class="font-semibold text-sm truncate pr-2">
              <.display_label label={@selected_item.label} />
              <MehungryWeb.RecipeComponents.condition_flag_badges
                flags={Map.get(@selected_item, :flags, [])}
                limit={2}
                class="mt-1"
              />
            </span>
            <button
              phx-click="clear_selection"
              phx-target={@myself}
              phx-stop-propagation
              class="text-parchment-dim hover:text-red-400 shrink-0 transition-colors"
            >
              <.icon name="hero-x-mark" class="h-4 w-4" />
            </button>
          </div>
        <% else %>
          <div class="h-full min-h-10 bg-ink-panel2 border border-[#3A3323] rounded-lg px-4 py-2 text-parchment-dim text-sm flex items-center transition-colors hover:border-paprika">
            {@placeholder || "Select an option..."}
          </div>
        <% end %>
      </div>

      <!-- Modal/Dropdown -->
      <div
        id={"select-modal-#{@unique_id}"}
        class={"fixed inset-0 bg-ink/80 flex items-center justify-center z-50 p-4 #{if @modal_open, do: "", else: "hidden"}"}
      >
        <div class="bg-ink-panel rounded-2xl ring-1 ring-ink-panel2 shadow-2xl shadow-black/50 max-w-lg w-full overflow-hidden">
          <div class="flex justify-between items-center p-4 border-b border-ink-panel2">
            <h3 class="text-lg font-display font-medium text-parchment overflow-hidden">
              {@modal_title || "Select Option"}
            </h3>
            <button
              phx-click="close_modal"
              phx-target={@myself}
              class="rounded-lg p-1.5 text-parchment-dim hover:text-parchment hover:bg-ink-panel2 transition-colors"
            >
              <.icon name="hero-x-mark" class="h-5 w-5" />
            </button>
          </div>
          <div class="p-6">
            <!-- Search Input -->
            <input
              type="text"
              id={"search-input-#{@unique_id}"}
              name="search_term"
              value={@search_term}
              placeholder="Search..."
              phx-keyup="search"
              phx-target={@myself}
              phx-debounce="300"
              class="w-full px-4 py-2 bg-ink border border-ink-panel2 rounded-lg text-parchment placeholder-parchment-dim focus:outline-none focus:border-paprika focus:ring-1 focus:ring-paprika transition-colors"
            />
          </div>
          <!-- Results List -->
          <div class="max-h-64 overflow-y-auto">
            <%= if @loading do %>
              <div class="text-center py-4 text-parchment-dim">Loading...</div>
            <% else %>
              <%= if Enum.empty?(@items) do %>
                <div class="text-center py-4 text-parchment-dim/70">No results found</div>
              <% else %>
                <ul class="space-y-1 px-4 pb-4">
                  <%= for item <- @items do %>
                    <li
                      phx-click="select_item"
                      phx-value-id={item.id}
                      phx-value-parent_id={@parent_id}
                      phx-target={@myself}
                      class="cursor-pointer hover:bg-ink-panel2 p-2 rounded-lg transition-colors"
                    >
                      <.display_label label={item.label} />
                      <MehungryWeb.RecipeComponents.condition_flag_badges
                        flags={Map.get(item, :flags, [])}
                        limit={2}
                        class="mt-1"
                      />
                    </li>
                  <% end %>
                </ul>
              <% end %>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def display_label(assigns) do
    ~H"""
    <div>
      <%= if String.contains?(@label, ",") do %>
        <% [first | rest] = String.split(@label, ",") %>
        <span class="font-semibold text-parchment">{first}</span>
        <span class="text-xs text-parchment-dim">{Enum.join(rest, ",")}</span>
      <% else %>
        <span class="font-semibold text-parchment">{@label}</span>
      <% end %>
    </div>
    """
  end

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:loading, false)
     |> assign(:items, [])
     |> assign(:search_term, "")
     |> assign(:modal_open, false)
     |> assign(:selected_id, nil)}
  end

  @impl true
  def update(assigns, socket) do
    # Generate a unique ID for this component instance
    unique_id = "#{assigns.id}_#{System.unique_integer([:positive])}"

    socket =
      socket
      |> assign(assigns)
      |> assign(:unique_id, unique_id)

    # Get the current value from the form
    input_key = String.to_atom(assigns.input_variable)
    current_id = get_field(assigns.form.source, input_key)

    # Load selected item if exists
    selected_item =
      if current_id do
        case assigns.get_by_id_func.(current_id) do
          nil ->
            nil

          item ->
            [%{label: assigns.label_function.(item), id: item.id}]
            |> then(&attach_flags(socket, &1))
            |> List.first()
        end
      else
        nil
      end

    {:ok,
     socket
     |> assign(:selected_item, selected_item)
     |> assign(:selected_id, current_id)}
  end

  @impl true
  def handle_event("open_modal", _, socket) do
    items = load_items(socket, "")

    {:noreply,
     socket
     |> assign(:modal_open, true)
     |> assign(:items, items)
     |> assign(:search_term, "")}
  end

  def handle_event("close_modal", _, socket) do
    {:noreply, assign(socket, :modal_open, false)}
  end

  def handle_event("search", %{"value" => search_term}, socket) do
    items = load_items(socket, search_term)

    {:noreply,
     socket
     |> assign(:items, items)
     |> assign(:search_term, search_term)}
  end

  def handle_event("select_item", %{"id" => id_str}, socket) do
    {id, _} = Integer.parse(id_str)

    selected_item = Enum.find(socket.assigns.items, fn item -> item.id == id end)

    form = socket.assigns.form
    input_key = String.to_atom(socket.assigns.input_variable)

    changeset = form.source
    changeset = change(changeset, %{input_key => id})

    form = %{form | source: changeset, params: Map.put(form.params, input_key, id)}

    if(!is_nil(Map.get(socket.assigns, :select_function))) do
      socket.assigns.select_function.(id)
    end

    # send(self(), {:selected_id, id})
    {:noreply,
     socket
     |> assign(:selected_item, selected_item)
     |> assign(:selected_id, id)
     |> assign(:form, form)
     |> assign(:modal_open, false)
     |> assign(:items, [])
     |> assign(:search_term, "")}
  end

  def handle_event("clear_selection", _, socket) do
    form = socket.assigns.form
    input_key = String.to_atom(socket.assigns.input_variable)

    changeset = form.source
    changeset = change(changeset, %{input_key => nil})

    form = %{form | source: changeset, params: Map.put(form.params, input_key, nil)}

    {:noreply,
     socket
     |> assign(:selected_item, nil)
     |> assign(:selected_id, nil)
     |> assign(:form, form)}
  end

  defp load_items(socket, search_term) do
    items =
      socket.assigns.item_function.(search_term)
      |> Enum.map(fn item ->
        %{label: socket.assigns.label_function.(item), id: item.id}
      end)

    attach_flags(socket, items)
  end

  # When a `flags_function` (`fn ids -> %{id => flags} end`) is provided, batch-load
  # health-condition flags for every result and stamp each item's `:flags`. No-ops
  # (leaves items untouched) for non-ingredient call sites that omit the function.
  defp attach_flags(socket, items) do
    case Map.get(socket.assigns, :flags_function) do
      nil ->
        items

      flags_function when is_function(flags_function, 1) ->
        flags_by_id = flags_function.(Enum.map(items, & &1.id))
        Enum.map(items, fn item -> Map.put(item, :flags, Map.get(flags_by_id, item.id, [])) end)
    end
  end
end
