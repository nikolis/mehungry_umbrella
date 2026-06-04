defmodule MehungryWeb.SearchSelect do
  use Phoenix.LiveComponent

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       query: "",
       open: false,
       filtered_options: [],
       # 👈 add this
       selected_label: nil
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="relative z-100">
      <!-- Hidden input (IMPORTANT for Phoenix forms) -->
      <input
        type="hidden"
        name={@field.name}
        id={@id}
        value={@field.value}
        phx-hook="SearchSelectHook"
        data-target={@id}
      />
      
    <!-- Input box -->
      <input
        type="text"
        value={@selected_label || ""}
        placeholder="Search..."
        phx-keyup="search"
        phx-target={@myself}
        phx-debounce="300"
        name="q"
      />
      <div>{@open}</div>
      <!-- Dropdown -->
      <%= if @open do %>
        <ul class="absolute bg-white border w-full max-h-40 overflow-y-auto z-10">
          <%= for {label, value} <- @filtered_options do %>
            <li
              class="p-2 hover:bg-gray-200 cursor-pointer"
              phx-click="select"
              phx-target={@myself}
              phx-value-value={value}
              phx-value-label={label}
            >
              {label}
            </li>
          <% end %>
        </ul>
      <% end %>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    options = assigns.options || []

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:filtered_options, options)}
  end

  @impl true
  def handle_event("search", %{"q" => query}, socket) do
    filtered =
      socket.assigns.options
      |> Enum.filter(fn {label, _value} ->
        String.contains?(String.downcase(label), String.downcase(query))
      end)

    {:noreply,
     assign(socket,
       query: query,
       filtered_options: filtered,
       open: true
     )}
  end

  def handle_event("select", %{"value" => value, "label" => label}, socket) do
    {:noreply,
     socket
     |> assign(:selected_label, label)
     |> assign(:open, false)
     |> push_event("set-value-#{socket.assigns.id}", %{value: value})}
  end

  def handle_event("toggle", _, socket) do
    {:noreply, assign(socket, :open, !socket.assigns.open)}
  end
end
