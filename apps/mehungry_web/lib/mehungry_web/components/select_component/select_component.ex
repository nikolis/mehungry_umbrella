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

    _form_params = assigns.form.params

    selected_items =
      MehungryWeb.SelectComponentUtils.get_selected_items(
        assigns.form.source.changes,
        Map.get(assigns.form, :params, nil),
        assigns.input_variable,
        label_function,
        assigns
      )

    existing_selected = Map.get(assigns.form.source.data, assigns.input_variable)

    # The user has explicitly cleared this select when the changeset carries the
    # field with a nil value. In that case we must not fall back to the persisted
    # value below — doing so snapped the widget back to the previous selection
    # (and hid the search box) instead of letting the user pick a replacement.
    changes = assigns.form.source.changes

    changeset_cleared? =
      is_map(changes) and Map.has_key?(changes, assigns.input_variable) and
        is_nil(Map.get(changes, assigns.input_variable))

    changeset_has_value? =
      is_map(changes) and Map.has_key?(changes, assigns.input_variable) and
        not is_nil(Map.get(changes, assigns.input_variable))

    # Sticky clear. The changeset-carried nil above is driven by a JS hook that
    # writes the hidden input then re-validates the form; that round-trip can lag
    # or race the very next keystroke in the search box. When it does, the
    # re-validate produces a changeset with NO change for this field, and
    # `get_selected_items/5` resurrects the persisted value straight from
    # `form.data` — snapping the widget back to the old selection on the first
    # character typed. So we also remember the clear in the component's own
    # socket and treat it as authoritative until a genuine new value appears.
    cleared? =
      changeset_cleared? or
        (Map.get(socket.assigns, :user_cleared, false) and not changeset_has_value?)

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
          if !cleared? and !is_nil(existing_selected) do
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

    # Covers the resurrection path the `[] ->` branch guard cannot: when the
    # changeset has no change for this field, `get_selected_items/5` returns the
    # persisted value from `form.data` directly (a non-empty list), so the guard
    # above never runs. Forcing empty here when cleared is what actually keeps a
    # deliberately-cleared single-select empty while the user types a search.
    selected_items = if cleared?, do: [], else: selected_items

    items = Enum.map(assigns.items, fn x -> {elem(x, 0), label_function.(x)} end)

    items =
      Enum.map(items, fn {x, y} ->
        {x, Mehungry.Food.NutrientMapper.humanize_nutrient_name(y)}
      end)

    presenting_items = Enum.slice(items, 0..10)

    socket =
      socket
      |> assign(:items, items)
      # The full, unfiltered option list. `:items` gets overwritten with the
      # filtered subset while searching, so searches must run against this stable
      # copy — otherwise each keystroke narrows an already-narrowed list (and a
      # single non-matching character empties it for good).
      |> assign(:all_items, items)
      |> assign(:mode, Map.get(assigns, :mode, :single))
      |> assign(:index, Map.get(assigns, :index, 0))
      |> assign(:presenting_items, presenting_items)
      # Preserve the dropdown's open/closed state across parent re-renders. The
      # form's `phx-change="validate"` fires update/2 on every keystroke; forcing
      # it back to `initial_open` here would race the `search` event and slam the
      # results dropdown shut mid-search. The component's own events
      # (search/toggle/close/select) are the source of truth once mounted.
      |> assign(
        :listing_open,
        Map.get(socket.assigns, :listing_open, Map.get(assigns, :initial_open, false))
      )
      |> assign(:selected_items, selected_items)
      # Optional rich presentation: a map of `id => %{image_url, subtitle}` the
      # caller can pass (e.g. recipes) so options/the chosen chip render a
      # thumbnail + subtitle. Absent (default `%{}`) → plain-name rendering, so
      # the unit/nutrient/ingredient call sites are unaffected.
      |> assign(:item_meta, Map.get(assigns, :item_meta, %{}))
      # Persist the sticky-clear intent (see `cleared?` above). Once a real value
      # is present again (the user picked a replacement) we drop it so a later
      # edit of the same row isn't wrongly held empty.
      |> assign(:user_cleared, cleared? and not changeset_has_value?)
      |> assign(:form, assigns.form)
      |> assign(:input_variable, assigns.input_variable)
      # The caller-supplied component `id` is unique per page (LiveView requires
      # it), so it — not the row `index` — is what makes this widget's DOM ids and
      # its client push_event name unique. Two `measurement_unit_id` selects (the
      # ingredient's default unit and a portion's unit) both live at index 0 and
      # would otherwise collide. Keep this in sync with `data-reference-index` in
      # render/1 and the `Hooks.SelectComponent` listener name in hooks.js.
      # Normalize to a binary — callers sometimes pass an integer id (e.g. a
      # recipe id), and sc_id is used in string concatenation for the DOM ids.
      |> assign(:sc_id, to_string(assigns.id))

    {:ok, socket}
  end

  def handle_event("search", %{"key" => _key, "value" => value}, socket) do
    items = search_items(value, socket.assigns.all_items)

    socket =
      socket
      |> assign(:presenting_items, items)
      |> assign(:items, items)
      |> assign(:listing_open, true)

    {:noreply, socket}
  end

  def handle_event("handle-item-click", %{"id" => id}, socket) do
    selected_item = Enum.find(socket.assigns.items, fn x -> elem(x, 0) == id end)
    selected_items = socket.assigns.selected_items ++ [selected_item]

    socket =
      socket
      |> assign(:listing_open, false)
      |> assign(:selected_items, selected_items)
      # A real selection ends any sticky-clear state (see update/2).
      |> assign(:user_cleared, false)

    # Pushes the message that the SelectComponent Hook is waiting for int he JS side
    selected_items =
      Enum.map(selected_items, fn x -> elem(x, 0) end)
      |> Enum.uniq()

    {:noreply,
     push_event(
       socket,
       "selected_id" <> socket.assigns.sc_id <> Atom.to_string(socket.assigns.input_variable),
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
      # Remember an explicit clear so a mid-search re-validate can't resurrect
      # the persisted selection from form.data (see update/2 `cleared?`).
      |> assign(:user_cleared, selected_items == [])

    selected_items = Enum.map(selected_items, fn x -> elem(x, 0) end)

    {:noreply,
     push_event(
       socket,
       "selected_id" <>
         socket.assigns.sc_id <>
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

  # Search used by the live search box. Prefix/substring matches come first (so
  # typing "chi" surfaces "Chicken soup" on the very first characters, which a
  # pure jaro-distance threshold never does for short queries), then typo-tolerant
  # fuzzy matches fill in. Both are accent/case-insensitive via `normalize/1`.
  def search_items(query, terms) do
    normalized_query = normalize(query)

    case normalized_query do
      "" ->
        Enum.slice(terms, 0..10)

      nq ->
        terms
        |> Enum.map(fn {_id, term} = item ->
          nt = normalize(term)

          score =
            cond do
              String.starts_with?(nt, nq) -> 3.0
              String.contains?(nt, nq) -> 2.0
              true -> String.jaro_distance(nt, nq)
            end

          {item, score}
        end)
        |> Enum.filter(fn {_item, score} -> score >= 0.40 end)
        |> Enum.sort_by(fn {_item, score} -> -score end)
        |> Enum.map(fn {item, _score} -> item end)
        |> Enum.slice(0..10)
    end
  end

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

    # Derive the submitted hidden value from the authoritative local selection
    # (not the possibly-stale `@form` field) so a deliberate clear stays cleared
    # and the parent form never resubmits the old id mid-search.
    assigns =
      Map.put(assigns, :hidden_value, Enum.map_join(assigns.selected_items, ",", &elem(&1, 0)))

    ~H"""
    <div
      class="w-full h-full"
      data-reference-id={@input_variable}
      data-reference-index={@sc_id}
      phx-hook="SelectComponent"
      id={"select_component_" <> @sc_id}
    >
      <.input field={@form[@input_variable]} type="hidden" value={@hidden_value} />
      <div
        class="h-full w-full max-w-lg "
        phx-click-away="close-listing"
        phx-target={@myself}
        id={"select-item_" <> @sc_id}
      >
        <!-- Start Component -->
        <div class="relative h-full">
          <.list_selected
            selected_items={@selected_items}
            mode={@mode}
            myself={@myself}
            form={@form}
            input_variable={@input_variable}
            item_meta={@item_meta}
          />
          <.list_search_result
            myself={@myself}
            listing_open={@listing_open}
            items={@items}
            selected_items={@selected_items}
            mode={@mode}
            item_meta={@item_meta}
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
        <.selected_item
          id={elem(x, 0)}
          myself={@myself}
          mode={@mode}
          name={elem(x, 1)}
          meta={Map.get(@item_meta, elem(x, 0))}
        />
      <% end %>

      <!-- Search Input -->
      <%= if Enum.empty?(@selected_items) do %>
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
    <div class="w-full h-full min-h-10 relative border border-[var(--sc-border,#475569)] rounded-lg bg-[var(--sc-bg,#334155)]">
      <div
        phx-click="handle-selected-item-click"
        phx-value-id={@id}
        phx-target={@myself}
        tabindex="0"
        class="rounded-lg px-2 py-2 h-full text-left cursor-pointer flex items-center gap-2 pr-7 text-white"
      >
        <.item_content name={@name} meta={@meta} />
        <.icon
          name="hero-x-mark"
          class="absolute right-2 top-1/2 -translate-y-1/2 z-20 text-slate-400 hover:text-red-400 h-3.5 w-3.5"
        />
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
      <ul class="text-white absolute left-0 right-0 bg-[var(--sc-dropdown-bg,#334155)] rounded-lg shadow-lg max-h-60 overflow-y-auto min-w-52 z-50">
        <%= if @listing_open do %>
          <%= for x <- @items do %>
            <.option_item
              myself={@myself}
              x={x}
              selected={MapSet.member?(@selected_ids, elem(x, 0))}
              mode={@mode}
              meta={Map.get(@item_meta, elem(x, 0))}
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
      class="flex items-center gap-2 cursor-pointer px-3 py-2 bg-[var(--sc-option-selected,#475569)] text-primary-300 hover:bg-[var(--sc-option-hover,#64748b)] relative z-50"
      phx-click="handle-selected-item-click"
      phx-value-id={elem(@x, 0)}
      phx-target={@myself}
    >
      <.icon name="hero-check" class="h-4 w-4 text-primary-400 flex-shrink-0" />
      <.item_content name={elem(@x, 1)} meta={@meta} />
    </li>
    """
  end

  defp option_item(%{selected: false} = assigns) do
    ~H"""
    <li
      class={
        "flex items-center gap-2 cursor-pointer px-3 py-2 bg-[var(--sc-option-bg,#334155)] hover:bg-[var(--sc-option-hover,#64748b)] relative z-50 " <>
          if(is_nil(@meta), do: "pl-9", else: "")
      }
      phx-click="handle-item-click"
      phx-value-id={elem(@x, 0)}
      phx-target={@myself}
    >
      <.item_content name={elem(@x, 1)} meta={@meta} />
    </li>
    """
  end

  # Shared option/chip content: a thumbnail + title + subtitle when the caller
  # supplied `meta` for this item (recipes), else just the plain name (units,
  # nutrients, ingredients). `meta` is nil for items without metadata.
  defp item_content(%{meta: meta} = assigns) when is_map(meta) do
    ~H"""
    <%= if @meta[:image_url] do %>
      <img
        src={@meta.image_url}
        alt=""
        loading="lazy"
        class="h-9 w-9 rounded-md object-cover flex-shrink-0 bg-black/20"
      />
    <% else %>
      <div class="h-9 w-9 rounded-md bg-black/20 flex-shrink-0 flex items-center justify-center text-sm">
        🍽
      </div>
    <% end %>
    <div class="min-w-0 flex-1 text-left">
      <div class="truncate text-sm">{@name}</div>
      <div :if={@meta[:subtitle] not in [nil, ""]} class="truncate text-xs text-slate-400">
        {@meta.subtitle}
      </div>
    </div>
    """
  end

  defp item_content(assigns) do
    ~H"""
    <span class="truncate text-sm">{@name}</span>
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
      class="absolute top-2 right-2  -translate-y-1/2 cursor-pointer focus:outline-none z-20"
      style=" top: 50%; transform: translateY(-50%);"
      tabindex="-1"
    >
      <path d="M12 17.414 3.293 8.707l1.414-1.414L12 14.586l7.293-7.293 1.414 1.414L12 17.414z" />
    </svg>
    """
  end
end
