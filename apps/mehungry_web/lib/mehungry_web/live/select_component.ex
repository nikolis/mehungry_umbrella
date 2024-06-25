defmodule MehungryWeb.SelectComponent do
  use MehungryWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div class="col-span-2" data-reference-id={@input_variable} data-reference-index={@form.index} phx-hook="SelectComponent" id={"select_component"<> Integer.to_string(@form.index) <> @input_variable } >

    <.input  field={@form[String.to_atom(@input_variable)]} type="hidden"  />
    <div class="w-full max-w-lg " phx-click-away="close-listing" phx-target={@myself} id={"select-item" <> Integer.to_string(@form.index) <> @input_variable }>
      <!-- Start Component -->
      <div class="relative">
        <!-- Start Item Tags And Input Field -->
        <div
          class="flex items-center justify-between px-1 border border-2 rounded-md relative pr-8 bg-white">
          <ul class="flex flex-wrap items-center w-full">
            <!-- Tags (Selected) -->
            <%=  for x <- @selected_items do %>
              <div>
                <li
                  phx-click="handle-selected-item-click"
                  phx-value-id={x.id}
                  phx-target={@myself}
                  tabindex="0"
                  class="relative m-1 px-2 py-1.5 border rounded-md cursor-pointer hover:bg-gray-100 after:content-['x'] after:ml-1.5 after:text-red-300 outline-none focus:outline-none ring-0 focus:ring-2 focus:ring-amber-300 ring-inset transition-all"> 
                  <%= x.label %>
                </li>
              </div>
            <% end %>
            <!-- Search Input -->

            <%= if Enum.empty?(@selected_items) do %>
                <.input  phx-focus="search_input_focus" phx-target={@myself} field={@form[String.to_atom("search_input"<> Integer.to_string(@form.index)<>@input_variable)]} type="text" class="test flex-grow py-2 px-2 mx-1 my-1.5 outline-none focus:outline-none focus:ring-amber-300 focus:ring-2 ring-inset transition-all rounded-md w-full"/>
            <% end %>
            <!-- Arrow Icon -->
            <svg
              phx-click="toggle-listing"
              phx-target={@myself}
              width="24"
              height="24"
              stroke-width="0"
              fill="#ccc"
              class="absolute right-2 top-1/2 -translate-y-1/2 cursor-pointer focus:outline-none"
              tabindex="-1">
              <path
                d="M12 17.414 3.293 8.707l1.414-1.414L12 14.586l7.293-7.293 1.414 1.414L12 17.414z"
              />
            </svg>
          </ul>
        </div>
        <!-- End Item Tags And Input Field -->

          <!-- Start Items List -->
                <div >
                  <ul
                    class="w-full list-none   border-t-0 rounded-md focus:outline-none overflow-y-auto outline-none focus:outline-none bg-white absolute left-0 bottom-100 max-h-56	bg-white z-50">

            <%= if @listing_open do %>
              <%=  for x <- @items do %>
                   <!-- Item Element -->
                    <div class="relative z-50">
                      <div class="bg-white">
                        <li class="hover:bg-amber-200 cursor-pointer px-2 py-2 bg-white" phx-click="handle-item-click" phx-value-id={x.id} id={Integer.to_string(x.id)}phx-target={@myself}>
                          <%= x.label %>
                        </li>
                      </div>
                    </div>

                    <!-- Empty Text -->
                    <div >
                      <li class="cursor-pointer px-2 py-2 text-gray-400">
                      </li>
                    </div>
              <% end %>
            <% end %>
                  </ul>
                </div>

        <!-- End Items List -->
      </div>
      <!-- End Component -->
      </div>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    selected_items =
      case Map.get(socket.assigns, :selected_items) do
        [] ->
          case assigns.form.params["measurement_unit_id"] do
            nil ->
              []

            id ->
              if is_nil(Map.get(assigns, :items)) do
                []
              else
                Enum.find(assigns.items, [], fn x -> x.id == id end)
              end
          end

        nil ->
          case assigns.form.params["measurement_unit_id"] do
            nil ->
              []

            id ->
              if is_nil(Map.get(assigns, :items)) do
                []
              else
                Enum.find(assigns.items, [], fn x -> x.id == id end)
              end
          end

        [only_one] ->
          [only_one]

        other ->
          other
      end

    items = Enum.map(assigns.items, fn x -> %{label: x.name, id: x.id} end)
    presenting_items = Enum.slice(items, 0..10)

    socket =
      socket
      |> assign(:items, items)
      |> assign(:presenting_items, presenting_items)
      |> assign(:listing_open, Map.get(assigns, :initial_open, false))
      |> assign(:selected_items, selected_items)
      |> assign(:form, assigns.form)
      |> assign(:input_variable, assigns.input_variable)

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"search_input" => _search_string}, socket) do
    socket =
      socket
      |> assign(:listing_open, true)

    {:noreply, socket}
  end

  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("window-blur", _, socket) do
    socket =
      socket
      |> assign(:listing_open, false)

    {:noreply, socket}
  end

  def handle_event("search_input_focus", _, socket) do
    socket =
      socket
      |> assign(:listing_open, true)

    {:noreply, socket}
  end

  def handle_event("toggle-listing", _, socket) do
    socket =
      socket
      |> assign(:listing_open, !socket.assigns.listing_open)

    {:noreply, socket}
  end

  def handle_event("close-listing", _, socket) do
    socket =
      socket
      |> assign(:listing_open, false)

    {:noreply, socket}
  end

  def handle_event("handle-selected-item-click", %{"id" => id}, socket) do
    {id, _} = Integer.parse(id)

    selected_items = Enum.filter(socket.assigns.selected_items, fn x -> x.id != id end)

    socket =
      socket
      |> assign(:selected_items, selected_items)

    {:noreply, socket}
  end

  def handle_event("handle-item-click", %{"id" => id}, socket) do
    {id, _} = Integer.parse(id)

    selected_item = Enum.find(socket.assigns.items, fn x -> x.id == id end)
    selected_items = Enum.into(socket.assigns.selected_items, [selected_item])

    socket =
      socket
      |> assign(:listing_open, false)
      |> assign(:selected_items, selected_items)

    {:noreply,
     push_event(
       socket,
       "selected_id" <>
         Integer.to_string(socket.assigns.form.index) <> socket.assigns.input_variable,
       %{id: id}
     )}
  end
end
