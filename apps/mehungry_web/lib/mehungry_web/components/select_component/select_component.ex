defmodule MehungryWeb.SelectComponent do
  @moduledoc """
  A module to facilitate Select item widget of forms this module is tightly couppled with the Hooks.SelectComponent in the JS side of things 

  expects 
  items: %{id: String, name: String}
  form: Form(The form that the widget is going to work on)
  input_variable: Atom an input variable which is the Field of the Form that this widget is going to operate  
  """
  use MehungryWeb, :live_component

  @impl true
  def update(assigns, socket) do
    label_function =
      case Map.get(assigns, :label_function) do
        nil ->
          fn x -> elem(x, 1) end

        label_f ->
          label_f
      end

    form_params = assigns.form.params

    selected_items =
      MehungryWeb.SelectComponentUtils.get_selected_items(
        assigns.form.source.changes,
        Map.get(assigns.form, :params, nil),
        assigns.input_variable,
        label_function,
        assigns
      )

    existing_selected = Map.get(assigns.form.source.data, assigns.input_variable)

    selected_items =
      case is_map(selected_items) do
        true ->
          {selected_items.id, selected_items.name}

        false ->
          selected_items
      end

    selected_items =
      case selected_items do
        [] ->
          if !is_nil(existing_selected) do
            items =
              Enum.filter(assigns.items, fn x ->
                elem(x, 0) == Integer.to_string(existing_selected)
              end)
          else
            []
          end

        other ->
          other
      end

    selected_items_vals =
      Enum.reduce(Enum.map(selected_items, fn {x, y} -> x end), "", fn acc, x ->
        case String.length(acc) == 0 do
          true ->
            x

          false ->
            acc <> "," <> x
        end
      end)

    items = Enum.map(assigns.items, fn x -> {elem(x, 0), label_function.(x)} end)

    items =
      Enum.map(items, fn {x, y} ->
        {x, MehungryWeb.NutrientMapper.humanize_nutrient_name(y)}
      end)

    presenting_items = Enum.slice(items, 0..10)

    socket =
      socket
      |> assign(:items, items)
      |> assign(:mode, Map.get(assigns, :mode, :single))
      |> assign(:index, Map.get(assigns, :index, 0))
      |> assign(:presenting_items, presenting_items)
      |> assign(:listing_open, Map.get(assigns, :initial_open, false))
      |> assign(:selected_items, selected_items)
      |> assign(:form, assigns.form)
      |> assign(:input_variable, assigns.input_variable)

    {:ok, socket}
  end

  def handle_event("search", %{"key" => key, "value" => value}, socket) do
    items = fuzzy_match(value, socket.assigns.items)

    socket =
      socket
      |> assign(:presenting_items, items)
      |> assign(:items, items)
      |> assign(:listing_open, true)

    {:noreply, socket}
  end

  def to_human(term) do
    Map.get(@lookup, normalize(term), term)
  end

  def normalize(str) do
    str
    |> String.downcase()
    |> String.trim()
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/[^a-z0-9\s]/u, "")
  end

  def build_lookup(map) do
    Enum.reduce(map, %{}, fn {canonical, synonyms}, acc ->
      all_terms = [canonical | synonyms]

      Enum.reduce(all_terms, acc, fn term, acc2 ->
        Map.put(acc2, normalize(term), canonical)
      end)
    end)
  end

  def exact_match(query, lookup) do
    Map.get(lookup, normalize(query))
  end

  # query => strimg 
  # terms => list<{id, string}>
  # result => list <{id, string}>
  def fuzzy_match(query, terms, threshold \\ 0.40) do
    normalized_query = normalize(query)

    terms
    |> Enum.map(fn {id, term} ->
      score = String.jaro_distance(normalize(term), normalized_query)
      {id, term, score}
    end)
    |> Enum.filter(fn {_id, _term, score} -> score >= threshold end)
    |> Enum.sort_by(fn {_id, _term, score} -> -score end)
    |> Enum.map(fn {id, term, _} -> {id, term} end)
    |> Enum.slice(0..10)
  end

  def find_nutrient(query, lookup) do
    case exact_match(query, lookup) do
      nil ->
        fuzzy_match(query, lookup)

      result ->
        [result]
    end
  end

  def handle_event("handle-item-click", %{"id" => id}, socket) do
    selected_item = Enum.find(socket.assigns.items, fn x -> elem(x, 0) == id end)
    selected_items = socket.assigns.selected_items ++ [selected_item]

    socket =
      socket
      |> assign(:listing_open, false)
      |> assign(:selected_items, selected_items)

    # Pushes the message that the SelectComponent Hook is waiting for int he JS side
    selected_items =
      Enum.map(selected_items, fn x -> elem(x, 0) end)
      |> Enum.uniq()

    index =
      if is_nil(Map.get(socket.assigns.form, :index, 0)) do
        0
      else
        socket.assigns.form.index
      end

    {:noreply,
     push_event(
       socket,
       "selected_id" <> Integer.to_string(index) <> Atom.to_string(socket.assigns.input_variable),
       %{id: selected_items}
     )}
  end

  def handle_event("handle-selected-item-click", %{"id" => id}, socket) do
    selected_items =
      Enum.filter(socket.assigns.selected_items, fn x -> elem(x, 0) != id end)

    socket =
      socket
      |> assign(:selected_items, selected_items)
      |> assign(:listing_open, false)

    selected_items = Enum.map(selected_items, fn x -> elem(x, 0) end)

    index =
      case socket.assigns.form.index do
        nil ->
          0

        anything ->
          anything
      end

    {:noreply,
     push_event(
       socket,
       "selected_id" <>
         Integer.to_string(index) <>
         Atom.to_string(socket.assigns.input_variable),
       %{id: selected_items}
     )}
  end

  def handle_event("window-blur", _, socket) do
    socket =
      socket
      |> assign(:listing_open, false)

    {:noreply, socket}
  end

  @impl true
  def handle_event("validate", %{"search_input" => _search_string}, socket) do
    socket =
      socket
      |> assign(:listing_open, true)

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

  # ----------------------------------------------------------------------------------Render --------------------------------------------------------------------------------------------->
  @impl true
  def render(assigns) do
    form = Map.get(assigns, :form, nil)

    index =
      case is_nil(form) do
        true ->
          0

        false ->
          index = Map.get(form, :index, 0)

          if is_nil(index) do
            0
          else
            index
          end
      end

    assigns = Map.put(assigns, :index, index)

    ~H"""
    <div
      class="w-full h-full"
      data-reference-id={@input_variable}
      data-reference-index={@index}
      phx-hook="SelectComponent"
      id={"select_component"<>  Atom.to_string(@input_variable) <> Integer.to_string(@index)}
    >
      <.input field={@form[@input_variable]} type="hidden" />
      <div
        class="h-full w-full max-w-lg "
        phx-click-away="close-listing"
        phx-target={@myself}
        id={"select-item"<> Atom.to_string(@input_variable) <> Integer.to_string(@index)}
      >
        <!-- Start Component -->
        <div class="relative h-full">
          <.list_selected
            selected_items={@selected_items}
            mode={@mode}
            myself={@myself}
            form={@form}
            input_variable={@input_variable}
          />
          <.list_search_result
            myself={@myself}
            listing_open={@listing_open}
            items={@items}
            selected_items={@selected_items}
          />
        </div>
        <!-- End Component -->
      </div>
    </div>
    """
  end

  # ------------------------------------------------------------------------------- List Selected ------------------------------------------------------------------------------------

  def list_selected(%{mode: :multi} = assigns) do
    ~H"""
    <div class=" h-full flex activated:min-h-screen flex-col items-center justify-center overflow-hidden  col-span-2 sm:col-span-2 	 overflow-hidden">
      <!-- Tags (Selected) -->


        <!-- Search Input -->
      <%= if Enum.empty?(@selected_items)  or @mode == :multi do %>
        <.input_search
          myself={@myself}
          form={@form}
          selected_items={@selected_items}
          mode={@mode}
          input_variable={@input_variable}
          class="h-full text-2xl bg-black"
        />
      <% end %>
      <!-- Arrow Icon -->
    </div>
    """
  end

  def list_selected(assigns) do
    ~H"""
    <div class="">
      <!-- Tags (Selected) -->
      <%= for x <- @selected_items do %>
        <.selected_item id={elem(x, 0)} myself={@myself} mode={@mode} name={elem(x, 1)} />
      <% end %>
      
    <!-- Search Input -->
      <%= if Enum.empty?(@selected_items)  or @mode == :multi do %>
        <.input_search
          myself={@myself}
          form={@form}
          selected_items={@selected_items}
          mode={@mode}
          input_variable={@input_variable}
          class="h-full text-2xl bg-black"
        />
      <% end %>
      <!-- Arrow Icon -->
    </div>
    """
  end

  defp selected_item(%{mode: :multi} = assigns) do
    ~H"""
    <div
      phx-click="handle-selected-item-click"
      phx-value-id={@id}
      phx-target={@myself}
      tabindex="0"
      class="relative h-full w-fit my-2 mx-auto px-2 py-1.5 border rounded-md cursor-pointer hover:bg-gray-100 after:content-['x'] after:ml-1.5 after:text-red-300 outline-none focus:outline-none ring-0 focus:ring-2 focus:ring-amber-300 ring-inset transition-all"
    >
      {@name}
    </div>
    """
  end

  defp selected_item(%{mode: :single} = assigns) do
    ~H"""
    <div class="text-center w-full h-full relative">
      <div
        phx-click="handle-selected-item-click"
        phx-value-id={@id}
        phx-target={@myself}
        tabindex="0"
        class="border border-black border-2 h-full text-left border-greyfriend2 cursor-pointer rounded-lg "
      >
        <div class="h-full flex flex-col  justify-center p-4 ">
          <div class="self-center text-ellipsis text-center overflow-hidden px-1 leading-4">
            {@name}
          </div>
        </div>
        <.icon name="hero-x-mark" class="absolute right-1 top-1  z-20 opacity-70 h-3 w-3" />
      </div>
    </div>
    """
  end

  defp input_search(%{mode: :multi} = assigns) do
    ~H"""
    <div class="relative h-full">
      <%= for x <- @selected_items do %>
        <.selected_item id={elem(x, 0)} myself={@myself} mode={@mode} name={elem(x, 1)} />
      <% end %>

      <.input
        phx-focus="search_input_focus"
        phx-target={@myself}
        phx-keyup="search"
        field={
          @form[
            String.to_atom("search_input" <> Atom.to_string(@input_variable))
          ]
        }
        type="text"
        class="h-full test flex-grow p-4  outline-none focus:outline-none focus:ring-amber-300 focus:ring-2 ring-inset transition-all rounded-md w-full relative"
      />
      <.arrow_down_svg myself={@myself} selected_items_length={length(@selected_items)} mode={@mode} />
    </div>
    """
  end

  defp input_search(assigns) do
    ~H"""
    <div class="relative h-full">
      <.input
        phx-focus="search_input_focus"
        phx-target={@myself}
        phx-keyup="search"
        field={
          @form[
            String.to_atom("search_input" <> Atom.to_string(@input_variable))
          ]
        }
        type="text"
        class="h-full test flex-grow p-4  outline-none focus:outline-none focus:ring-amber-300 focus:ring-2 ring-inset transition-all rounded-md w-full relative"
      />
      <.arrow_down_svg myself={@myself} selected_items_length={length(@selected_items)} mode={@mode} />
    </div>
    """
  end

  # ----------------------------------------------------------------------------------------------------- END List Selected   ------------------------------------------------------
  # ----------------------------------------------------------------------------------------------------- Search Result -----------------------------------------------------------
  defp list_search_result(assigns) do
    ~H"""
    <div>
      <ul class="w-full list-none   border-t-0 rounded-md focus:outline-none overflow-y-auto outline-none focus:outline-none bg-white absolute left-0 bottom-100 max-h-56	bg-white z-50">
        <%= if @listing_open do %>
          <%= for x <- @items do %>
            <!-- Item Element -->
            <.option_item myself={@myself} x={x} />
            <!-- Empty Text -->
            <div>
              <li class="cursor-pointer px-2 py-2 text-gray-400"></li>
            </div>
          <% end %>
        <% end %>
      </ul>
    </div>
    """
  end

  defp option_item(assigns) do
    ~H"""
    <div class="relative z-50">
      <div class="bg-white">
        <li
          class="hover:bg-amber-200 cursor-pointer px-2 py-2 bg-white "
          phx-click="handle-item-click"
          phx-value-id={elem(@x, 0)}
          id={elem(@x, 0)}
          phx-target={@myself}
        >
          {elem(@x, 1)}
        </li>
      </div>
    </div>
    """
  end

  # ----------------------------------------------------------------------------------------------------- Search Result -----------------------------------------------------------

  defp arrow_down_svg(%{mode: :single, selected_items_length: selected_length} = assigns)
       when selected_length > 0 do
    ~H"""
    <div></div>
    """
  end

  defp arrow_down_svg(assigns) do
    ~H"""
    <svg
      phx-click="toggle-listing"
      phx-target={@myself}
      width="24"
      height="24"
      stroke-width="0"
      fill="#ccc"
      class="absolute right-2 bottom-1 -translate-y-1/2 cursor-pointer focus:outline-none z-50"
      tabindex="-1"
    >
      <path d="M12 17.414 3.293 8.707l1.414-1.414L12 14.586l7.293-7.293 1.414 1.414L12 17.414z" />
    </svg>
    """
  end
end
