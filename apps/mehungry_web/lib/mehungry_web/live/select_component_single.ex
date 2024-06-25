defmodule MehungryWeb.SelectComponentSingle do
  use MehungryWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div class="col-span-2" data-reference-id={@input_variable} data-reference-index={@form.index} phx-hook="SelectComponent" id={"select_component"<> Integer.to_string(@form.index) <> @input_variable } >

    <.input  field={@form[String.to_atom(@input_variable)]} type="hidden"  />
      <!-- Start Component -->
      <div class="h-full relative">
        <!-- Start Item Tags And Input Field -->
            <!-- Tags (Selected) -->
            <%=  for x <- @selected_items do %>
              <div class="text-center w-full h-full">
                <div
                  phx-click="handle-selected-item-click"
                  phx-value-id={x.id}
                  phx-target={@myself}
                  tabindex="0"
                  class="border border-2 h-full text-left rounded-md border-greyfriend2"> 
                  <span class="absolute  bottom-1/3"> <%= x.label %> </span>
                  <.icon name="hero-x-mark-solid" class="absolute right-1  z-50 opacity-70" />

                </div>
              </div>
            <% end %>
            <!-- Search Input -->

            <%= if Enum.empty?(@selected_items) do %>
                <.input  phx-focus="search_input_focus" phx-target={@myself} field={@form[String.to_atom("search_input"<> Integer.to_string(@form.index)<>@input_variable)]} myself={@myself} type="select_component" class="test flex-grow py-2 px-2 outline-none focus:outline-none focus:ring-amber-300 focus:ring-2 ring-inset transition-all rounded-md w-full"/>
            <% end %>
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
