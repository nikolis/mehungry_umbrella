defmodule MehungryWeb.SelectComponentDeep do
  use MehungryWeb, :live_component
  import Ecto.Changeset, only: [get_field: 2, change: 2]

  @impl true
  def render(assigns) do
    ~H"""
    <div
      class="h-full relative rounded-lg border-2 border-slate-700 "
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
      <div phx-click="open_modal" phx-target={@myself} class="w-full cursor-pointer">
        <%= if @selected_item do %>
          <div class="bg-slate-700 border border-slate-800 rounded-lg text-white rounded-lg p-2 flex justify-between items-center">
            <span class="font-semibold">
              <.display_label label={@selected_item.label} />
            </span>
            <button
              phx-click="clear_selection"
              phx-target={@myself}
              phx-stop-propagation
              class="text-gray-100 hover:text-red-500"
            >
              <.icon name="hero-x-mark" class="h-4 w-4" />
            </button>
          </div>
        <% else %>
          <div class="overflow-hidden  h-full border border-slate-800 bg-slate-700 border-2 rounded-lg p-4 text-gray-500">
            {@placeholder || "Select an option..."}
          </div>
        <% end %>
      </div>
      
    <!-- Modal/Dropdown -->
      <div
        id={"select-modal-#{@unique_id}"}
        class={"fixed inset-0 bg-black/50 rounded-lg border-2 border-slate-700 flex items-center justify-center z-50 #{if @modal_open, do: "", else: "hidden"}"}
      >
        <div class="bg-slate-800 rounded-xl max-w-lg w-full mx-4 overflow-hidden ">
          <div class="flex justify-between items-center p-4 border-b border-slate-700 bg-slate-800">
            <h3 class="text-lg font-semibold overflow-hidden">{@modal_title || "Select Option"}</h3>
            <button phx-click="close_modal" phx-target={@myself}>
              <.icon name="hero-x-mark" class="h-5 w-5 text-white" />
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
              class="w-full px-4 py-2 bg-slate-700 border border-slate-600 rounded-lg text-white focus:outline-none focus:border-primary-500 focus:ring-1 focus:ring-primary-500"
            />
          </div>
          <!-- Results List -->
          <div class="max-h-64 overflow-y-auto">
            <%= if @loading do %>
              <div class="text-center py-4">Loading...</div>
            <% else %>
              <%= if Enum.empty?(@items) do %>
                <div class="text-center py-4 text-gray-500">No results found</div>
              <% else %>
                <ul class="space-y-1 p-4">
                  <%= for item <- @items do %>
                    <li
                      phx-click="select_item"
                      phx-value-id={item.id}
                      phx-value-parent_id={@parent_id}
                      phx-target={@myself}
                      class="cursor-pointer hover:bg-slate-700 p-2 rounded transition-colors"
                    >
                      <.display_label label={item.label} />
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
        <span class="font-semibold text-white">{first}</span>
        <span class="text-xs text-slate-500">{Enum.join(rest, ",")}</span>
      <% else %>
        <span class="font-semibold">{@label}</span>
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
          nil -> nil
          item -> %{label: assigns.label_function.(item), id: item.id}
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
    socket.assigns.item_function.(search_term)
    |> Enum.map(fn item ->
      %{label: socket.assigns.label_function.(item), id: item.id}
    end)
  end
end
