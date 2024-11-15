defmodule MehungryWeb.SelectComponentSingle2 do
  use MehungryWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div class=" flex activated:min-h-screen flex-col items-center justify-center overflow-hidden  col-span-4 sm:col-span-2 h-full max-h-18	 overflow-hidden">
      <!-- modal trigger -->
      <!-- hidden toggle -->
      <%= if @selected_items do %>
        <div class="text-center w-full h-full relative">
          <div
            phx-click="handle-selected-item-click"
            phx-value-id={@selected_items.id}
            phx-target={@myself}
            tabindex="0"
            class="border border-black border-2 h-full text-left border-greyfriend2 cursor-pointer rounded-lg "
          >
            <div class="h-full flex flex-col  justify-center p-1">
              <div class="self-center text-ellipsis text-center overflow-hidden px-1 leading-4">
                <.get_label label={Mehungry.Utils.remove_parenthesis(@selected_items.label)} />
              </div>
            </div>
            <.icon name="hero-x-mark" class="absolute right-1 top-1  z-20 opacity-70 h-3 w-3" />
          </div>
        </div>
      <% else %>
        <div class="h-full w-full border-2 rounded-lg relative border-greyfriend2">
          <label
            for={"tw-modal" <> Integer.to_string(@form.index)}
            class="active:bg-transparent h-full w-full absolute top-0 bottom-0 left-0 right-0  cursor-pointer  rounded  text-greyfriend3  "
          >
          </label>
        </div>
      <% end %>

      <input
        tabindex="-1"
        type="checkbox"
        phx-change="other"
        id={"tw-modal" <> Integer.to_string(@form.index)   }
        ref-input={Integer.to_string(@form.index)}
        class="peer fixed appearance-none opacity-0 hidden"
      />
      <!-- modal -->
      <label
        for={"tw-modal" <> Integer.to_string(@form.index)}
        class="z-40 pointer-events-none invisible fixed inset-0 flex cursor-pointer items-center justify-center overflow-hidden overscroll-contain bg-slate-700/30 opacity-0 transition-all duration-200 ease-in-out peer-checked:pointer-events-auto peer-checked:visible peer-checked:opacity-100 peer-checked: [&>*]:translate-y-0 peer-checked:[&>*]:scale-100"
      >
        <!-- modal box -->
        <label class="max-h-[calc(100vh -5 em)] h-5/6 sm:h-4/6 md:h-3/6 mx-4 w-full  max-w-lg scale-90 overflow-y-auto overscroll-contain rounded-md bg-white p-6 text-black shadow-2xl transition ">
          <div class="fixed  top-0 bottom-0 right-0 left-0 bg-white p-6" style="">
            <!--- modal content -->
            <h3 class="p-2 text-center">Search ingredient</h3>
            <.live_component
              module={MehungryWeb.SelectComponentSingle}
              form={@form}
              item_function={fn x -> Mehungry.Food.search_ingredient_alt(x) end}
              get_by_id_func={fn x -> Mehungry.Food.get_ingredient!(x) end}
              input_variable="ingredient_id"
              id={"ingredient_search_component" <> Integer.to_string(@form.index)}
            />
            <!-- modal  content -->
          </div>
        </label>
      </label>
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
