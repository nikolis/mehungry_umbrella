defmodule MehungryWeb.SelectComponentSingleMemory2 do
  use MehungryWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div
      class="w-full "
      data-reference-id={@input_variable}
      data-reference-index={@form.index}
      phx-hook="SelectComponent"
      id={@id}
    >
      <.input field={@form[String.to_atom(@input_variable)]} type="hidden" />
      <!-- Start Component -->
      <.focus_wrap
        id={
          if is_nil(@form.index) do
            "select_component_focus_wrap" <> @input_variable
          else
            "select_component_focus_wrap" <> Integer.to_string(@form.index) <> @input_variable
          end
        }
        class="h-full"
        phx-click-away={JS.push("close-listing", target: @myself)}
      >
        <div class="h-full relative">
          <!-- Start Item Tags And Input Field -->
          <!-- Tags (Selected) -->
          <%= if @selected_items do %>
            <div class="text-center w-full h-full">
              <div
                phx-click="handle-selected-item-click"
                phx-value-id={@selected_items.id}
                phx-target={@myself}
                tabindex="0"
                class="border border-2 h-full text-left border-greyfriend2 cursor-pointer rounded-lg"
              >
                <div class="h-full flex flex-col  justify-center py-2">
                  <div class="self-center text-ellipsis overflow-hidden  ">
                    <%= @selected_items.label %>
                  </div>
                </div>
                <.icon name="hero-x-mark-solid" class="absolute right-1 top-0  z-50 opacity-70" />
              </div>
            </div>
          <% end %>
          <!-- Search Input -->
          <%= if is_nil(@selected_items) do %>
            <.input
              phx-change="validate"
              phx-focus="search_input_focus"
              phx-target={@myself}
              value=""
              name="search_input"
              myself={@myself}
              type="select_component"
              class="text-sm	 flex-grow py-2 px-2 outline-none focus:outline-none focus:ring-amber-300 focus:ring-2 ring-inset transition-all  w-full "
            />
          <% end %>
          <!-- End Item Tags And Input Field -->
            <!-- Start Items List -->
          <div>
            <ul class="w-full list-none border-t-0
             focus:outline-none overflow-y-auto 
             outline-none focus:outline-none 
             bg-white absolute left-0 bottom-100 
             bg-white z-50 max-h-52 shadow-lg">
              <%= if @listing_open do %>
                <%= for {x, index}  <- Enum.with_index(@items_filtered) do %>
                  <!-- Item Element -->
                  <div class="relative z-50 h-full">
                    <div class="bg-white h-full">
                      <%= if index == 0   and !is_nil(@form.index) do %>
                        <li
                          class="h-full hover:bg-amber-200 cursor-pointer px-2 py-2 bg-white"
                          phx-click="handle-item-click"
                          phx-value-id={x.id}
                          id={Integer.to_string(x.id)}
                          phx-target={@myself}
                          phx-hook="SelectComponentList"
                        >
                          <%= x.label %>
                        </li>
                      <% else %>
                        <li
                          class="h-full hover:bg-amber-200 cursor-pointer px-2 py-2 bg-white"
                          phx-click="handle-item-click"
                          phx-value-id={x.id}
                          id={Integer.to_string(x.id)}
                          phx-target={@myself}
                        >
                          <%= x.label %>
                        </li>
                      <% end %>
                    </div>
                  </div>
                  <!-- Empty Text -->
                  <div>
                    <li class="cursor-pointer px-2 py-2 text-gray-400"></li>
                  </div>
                <% end %>
              <% end %>
            </ul>
          </div>
          <!-- End Items List -->
        </div>
      </.focus_wrap>
      <!-- End Component -->
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    id =
      if is_nil(assigns.form.index) do
        "select_component" <> assigns.input_variable
      else
        "select_component" <> Integer.to_string(assigns.form.index) <> assigns.input_variable
      end

    selected_items =
      MehungryWeb.SelectComponentUtils.get_selected_items(
        assigns.form.params,
        assigns.input_variable,
        assigns
      )

    label_function =
      case Map.get(assigns, :label_function) do
        nil ->
          fn x -> x.name end

        label_f ->
          label_f
      end

    # Create the content
    items_filtered =
      if is_nil(selected_items) do
        if Map.get(socket.assigns, :original_items) do
          if socket.assigns.original_items == assigns.items do
            socket.assigns.items_filtered
          else
            presenting_items = Enum.slice(assigns.items, 0..10)
            Enum.map(presenting_items, fn x -> %{label: label_function.(x), id: x.id} end)
          end
        else
          presenting_items = Enum.slice(assigns.items, 0..10)
          Enum.map(presenting_items, fn x -> %{label: label_function.(x), id: x.id} end)
        end
      else
        nil
      end

    socket =
      socket
      |> assign(:original_items, items_filtered)
      |> assign(:items_filtered, items_filtered)
      |> assign(:listing_open, Map.get(assigns, :initial_open, false))
      |> assign(:selected_items, selected_items)
      |> assign(:form, assigns.form)
      |> assign(:input_variable, assigns.input_variable)
      |> assign(:label_function, label_function)
      |> assign(:id, id)

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"search_input" => search_string}, socket) do
    items_filtered =
      Seqfuzz.filter(socket.assigns.original_items, search_string, fn x -> x.label end)

    socket =
      socket
      |> assign(:listing_open, true)
      |> assign(:items_filtered, items_filtered)

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

  def handle_event("handle-selected-item-click", _, socket) do
    socket =
      socket
      |> assign(:selected_items, nil)

    {:noreply,
     push_event(
       socket,
       "selected_id" <> socket.assigns.input_variable,
       %{id: nil}
     )}
  end

  def handle_event("handle-item-click", %{"id" => id}, socket) do
    {id, _} = Integer.parse(id)

    selected_item = Enum.find(socket.assigns.items_filtered, fn x -> x.id == id end)

    socket =
      socket
      |> assign(:listing_open, false)
      |> assign(:selected_items, selected_item)

    case is_nil(socket.assigns.form.index) do
      true ->
        {:noreply,
         push_event(
           socket,
           "selected_id" <>
             socket.assigns.input_variable,
           %{id: id}
         )}

      false ->
        {:noreply,
         push_event(
           socket,
           "selected_id" <>
             Integer.to_string(socket.assigns.form.index) <> socket.assigns.input_variable,
           %{id: id}
         )}
    end
  end
end
