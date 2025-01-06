defmodule MehungryWeb.SelectComponentSingle3 do
  use MehungryWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div class=" bg-red flex activated:min-h-screen flex-col items-center justify-center overflow-hidden  col-span-4 sm:col-span-2 h-full max-h-18	 overflow-hidden">
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
            phx-click={
              JS.show(to: "#modal-ingr" <> Integer.to_string(@form.index))
              |> JS.focus(
                to:
                  "#select_component" <>
                    Integer.to_string(@form.index) <>
                    "ingredient_idinnder"
              )
            }
            class="active:bg-transparent h-full w-full absolute top-0 bottom-0 left-0 right-0  cursor-pointer  rounded  text-greyfriend3  "
          >
          </label>
        </div>
      <% end %>
      <!-- modal -->
      <dialog
        class="z-50 fixed top-0 bottom-0  open:bg-grey bg-red"
        id={"modal-ingr" <> Integer.to_string(@form.index)}
      >
        <div
          id={"modal-background-bg" <> Integer.to_string(@form.index)}
          class="bg-zinc-50/90 fixed inset-0 transition-opacity"
          aria-hidden="true"
        />

        <.focus_wrap
          phx-window-keydown={JS.hide(to: "#modal-ingr" <> Integer.to_string(@form.index))}
          phx-key="escape"
          phx-click-away={JS.hide(to: "#modal-ingr" <> Integer.to_string(@form.index))}
          id={"my-modal" <> Integer.to_string(@form.index)}
          class="h-full"
          autofocus
        >
          <div class="bg-white relative py-8 px-14 rounded-lg min-h-40 pb-20">
            <h3 class="mb-4">Search Ingredient</h3>
            <.live_component
              module={MehungryWeb.SelectComponentSingle}
              form={@form}
              item_function={fn x -> Mehungry.Food.search_ingredient_alt(x) end}
              get_by_id_func={fn x -> Mehungry.Food.get_ingredient!(x) end}
              input_variable="ingredient_id"
              id={"ingredient_search_component" <> Integer.to_string(@form.index)}
            />

            <button
              phx-click={JS.hide(to: "#modal-ingr" <> Integer.to_string(@form.index))}
              class="absolute top-1 right-1"
            >
              <.icon name="hero-x-mark" class=" h-5 w-5" />
            </button>
          </div>
        </.focus_wrap>
        <!-- modal  content -->
      </dialog>
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
