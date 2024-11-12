defmodule MehungryWeb.SelectComponentSingle do
  use MehungryWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div
      class="col-span-4 sm:col-span-2 h-full max-h-16	"
      data-reference-id={@input_variable}
      data-reference-index={@form.index}
      phx-hook="SelectComponent"
      id={@id}
    >
      <.input field={@form[String.to_atom(@input_variable)]} type="hidden" />
      <!-- Start Component -->
      <.focus_wrap
        id={"select_component_focus_wrap"<> Integer.to_string(@form.index) <> @input_variable}
        class="h-full max-h-16"
        phx-click-away={JS.push("close-listing", target: @myself)}
      >
        <div class="h-full relative max-h-10 max-h-16	">
          <!-- Start Item Tags And Input Field -->
          <!-- Tags (Selected) -->
          <%= if @selected_items do %>
            <div class="text-center w-full h-full ">
              <div
                phx-click="handle-selected-item-click"
                phx-value-id={@selected_items.id}
                phx-target={@myself}
                tabindex="0"
                class="border border-2 h-full text-left border-greyfriend2 cursor-pointer rounded-lg"
              >
                <div class="h-full flex flex-col  justify-center p-1">
                  <div class="self-center text-ellipsis text-center overflow-hidden px-1 leading-4">
                    <.get_label label={Mehungry.Utils.remove_parenthesis(@selected_items.label)} />
                  </div>
                </div>
                <.icon name="hero-x-mark" class="absolute right-1 top-1  z-20 opacity-70 h-3 w-3" />
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
              name={"search_input" <> @id}
              myself={@myself}
              type="select_component"
              class="text-sm flex-grow py-2 px-2 outline-none focus:outline-none focus:ring-amber-300 focus:ring-2 ring-inset transition-all  w-full "
              id={@id <> "innder"}
            />
          <% end %>
          <!-- End Item Tags And Input Field -->
            <!-- Start Items List -->
          <div>
            <ul
              id={"ul"<>@id}
              class="w-full list-none border-t-0
             focus:outline-none overflow-y-auto 
             outline-none focus:outline-none 
             bg-white absolute left-0 bottom-100 
              bg-white z-50 max-h-52 shadow-lg"
            >
              <div id={@id<> "face"}></div>
              <%= if @listing_open do %>
                <%= for {x, index} <- Enum.with_index(@items_filtered) do %>
                  <!-- Item Element -->
                  <div class="relative z-50 h-full">
                    <div class="bg-white h-full">
                      <%= if index == 0  do %>
                        <li
                          class="h-full hover:bg-amber-200 cursor-pointer bg-white px-1 leading-4 "
                          phx-click="handle-item-click"
                          phx-value-id={x.id}
                          id={Integer.to_string(x.id)}
                          phx-target={@myself}
                          phx-hook="SelectComponentList"
                        >
                          <.get_label label={x.label} />
                        </li>
                      <% else %>
                        <li
                          class="h-full hover:bg-amber-200 cursor-pointer px-2 py-2 bg-white px-1 leading-4 "
                          phx-click="handle-item-click"
                          phx-value-id={x.id}
                          id={Integer.to_string(x.id)}
                          phx-target={@myself}
                        >
                          <.get_label label={x.label} />
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

  def get_label(assigns) do
    labels = String.split(assigns.label, ",")
    first = List.first(labels)
    labels = Enum.filter(labels, fn x -> x != first end)

    sub_script =
      Enum.reduce(labels, "", fn x, acc ->
        acc <>
          if String.length(acc) > 1 do
            ","
          else
            ""
          end <> x
      end)

    # sub_script = String.replace(sub_script, first, "")
    assigns = Map.put(assigns, :sub_script, sub_script)
    assigns = Map.put(assigns, :first, first)

    IO.inspect(assigns.first, label: "First")
    IO.inspect(assigns.sub_script, label: "Sub script")

    ~H"""
    <div>
      <span class="font-semibold">
        <%= @first %> <span class="text-xs font-light"><%= @sub_script %></span>
      </span>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    item_function = assigns.item_function
    get_by_id_func = assigns.get_by_id_func
    id = "select_component" <> Integer.to_string(assigns.form.index) <> assigns.input_variable

    label_function =
      case Map.get(assigns, :label_function) do
        nil ->
          fn x ->
            Mehungry.Utils.remove_parenthesis(x.name)
          end

        label_f ->
          label_f
      end

    selected_items =
      MehungryWeb.SelectComponentUtils.get_selected_items_database(
        assigns.form.params,
        assigns.input_variable,
        assigns,
        get_by_id_func
      )

    {items, items_filtered} =
      if is_nil(selected_items) do
        items = item_function.("")
        {items, Enum.map(items, fn x -> %{label: label_function.(x), id: x.id} end)}
      else
        {nil, nil}
      end

    socket =
      socket
      |> assign(:items, items)
      |> assign(:item_function, item_function)
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
  def handle_event("validate", params, socket) do
    search_input = "search_input" <> socket.assigns.id
    %{^search_input => search_string} = params
    items_filtered = socket.assigns.item_function.(search_string)
    # items_filtered = Seqfuzz.filter(socket.assigns.items, search_string, fn x -> x.label end)
    items =
      Enum.map(items_filtered, fn x -> %{label: socket.assigns.label_function.(x), id: x.id} end)

    socket =
      socket
      |> assign(:listing_open, true)
      |> assign(:items_filtered, items)

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
       "selected_id" <>
         Integer.to_string(socket.assigns.form.index) <> socket.assigns.input_variable,
       %{id: nil}
     )}
  end

  def handle_event("handle-item-click", %{"id" => id}, socket) do
    {id, _} = Integer.parse(id)

    selected_item = Enum.find(socket.assigns.items_filtered, fn x -> x.id == id end)

    # selected_item = %{label: socket.assigns.label_function.(selected_item), id: selected_item.id}

    socket =
      socket
      |> assign(:listing_open, false)
      |> assign(:selected_items, selected_item)

    {:noreply,
     push_event(
       socket,
       "selected_id" <>
         Integer.to_string(socket.assigns.form.index) <> socket.assigns.input_variable,
       %{id: id}
     )}
  end
end
