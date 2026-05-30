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
            Enum.filter(assigns.items, fn x ->
              elem(x, 0) == Integer.to_string(existing_selected)
            end)
          else
            []
          end

        id when is_integer(id) ->
          Enum.filter(assigns.items, fn x ->
            elem(x, 0) == Integer.to_string(id)
          end)

        id when is_binary(id) ->
          Enum.filter(assigns.items, fn x ->
            elem(x, 0) == id
          end)

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
            mode={@mode}
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
    <div class="w-fit h-full flex activated:min-h-screen flex-col items-center justify-center overflow-hidden  col-span-2 sm:col-span-2 	 ">
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
    <div class="text-white">
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
          class="h-full text-sm"
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
      class="relative h-full w-fit my-2 mx-auto px-2 py-1.5 border  border-slate-800 rounded-md cursor-pointer  after:content-['x'] after:ml-1.5 after:text-red-300 outline-none focus:outline-none ring-0 focus:ring-2  ring-inset transition-all text-white"
    >
      {@name}
    </div>
    """
  end

  defp selected_item(%{mode: :single} = assigns) do
    ~H"""
    <div class="w-full h-full min-h-10 relative border border-slate-600 rounded-lg bg-slate-700">
      <div
        phx-click="handle-selected-item-click"
        phx-value-id={@id}
        phx-target={@myself}
        tabindex="0"
        class="rounded-lg px-3 py-2 h-full text-left cursor-pointer flex items-center pr-6"
      >
        <div class="text-white text-sm truncate">
          {@name}
        </div>
        <.icon name="hero-x-mark" class="absolute right-2 top-1/2 -translate-y-1/2 z-20 text-slate-400 hover:text-red-400 h-3.5 w-3.5" />
      </div>
    </div>
    """
  end

  defp input_search(%{mode: :multi} = assigns) do
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
        class="h-full flex-grow outline-none focus:outline-none focus:ring-amber-300 focus:ring-2 ring-inset transition-all rounded-md w-full relative pr-16"
      />
      <%= if length(@selected_items) > 0 do %>
        <span class="absolute right-8 top-1/2 -translate-y-1/2 bg-primary-500 text-white text-xs font-semibold px-2 py-0.5 rounded-full pointer-events-none">
          {length(@selected_items)}
        </span>
      <% end %>
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
        class="h-full min-h-10 flex-grow outline-none focus:outline-none focus:ring-primary-500 focus:ring-2 ring-inset transition-all rounded-lg w-full relative text-sm"
      />
      <.arrow_down_svg myself={@myself} selected_items_length={length(@selected_items)} mode={@mode} />
    </div>
    """
  end

  # ----------------------------------------------------------------------------------------------------- END List Selected   ------------------------------------------------------
  # ----------------------------------------------------------------------------------------------------- Search Result -----------------------------------------------------------
  defp list_search_result(assigns) do
    selected_ids = MapSet.new(assigns.selected_items, &elem(&1, 0))
    assigns = assign(assigns, :selected_ids, selected_ids)

    ~H"""
    <div class="max-h-50 overflow-y-auto pr-2 w-fit">
      <ul class="text-white absolute left-0 bg-slate-700 max-h-40 overflow-y-scroll min-w-40 z-50">
        <%= if @listing_open do %>
          <%= for x <- @items do %>
            <.option_item
              myself={@myself}
              x={x}
              selected={MapSet.member?(@selected_ids, elem(x, 0))}
              mode={@mode}
            />
          <% end %>
        <% end %>
      </ul>
    </div>
    """
  end

  defp option_item(%{selected: true} = assigns) do
    ~H"""
    <li
      class="flex items-center gap-2 cursor-pointer px-3 py-2 bg-slate-600 text-primary-300 hover:bg-slate-500 relative z-50"
      phx-click="handle-selected-item-click"
      phx-value-id={elem(@x, 0)}
      phx-target={@myself}
    >
      <.icon name="hero-check" class="h-4 w-4 text-primary-400 flex-shrink-0" />
      {elem(@x, 1)}
    </li>
    """
  end

  defp option_item(%{selected: false} = assigns) do
    ~H"""
    <li
      class="flex items-center gap-2 cursor-pointer px-3 py-2 bg-slate-700 hover:bg-slate-500 pl-9 relative z-50"
      phx-click="handle-item-click"
      phx-value-id={elem(@x, 0)}
      phx-target={@myself}
    >
      {elem(@x, 1)}
    </li>
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
      class="absolute top-2 right-2  -translate-y-1/2 cursor-pointer focus:outline-none z-50"
      style=" top: 50%; transform: translateY(-50%);"
      tabindex="-1"
    >
      <path d="M12 17.414 3.293 8.707l1.414-1.414L12 14.586l7.293-7.293 1.414 1.414L12 17.414z" />
    </svg>
    """
  end
end
