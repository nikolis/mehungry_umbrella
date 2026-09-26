defmodule MehungryWeb.FoodsLive.Index do
  use MehungryWeb, :live_view
  alias Mehungry.Food
  alias Mehungry.Food.SpeciesSearch
  alias Mehungry.Health

  # How many compound suggestions to surface in the multi-select dropdown.
  @compound_suggestions 12

  @impl true
  def mount(_params, _session, socket) do
    language = socket.assigns[:current_language] || "en"
    {species, cursor_after} = load_page(language, nil)
    all_compounds = Food.list_linked_compounds()

    {:ok,
     socket
     |> assign(:species, species)
     |> assign(:cursor_after, cursor_after)
     |> assign(:query, "")
     |> assign(:show_filters, false)
     # The two filter dimensions are mutually exclusive — the user filters by one
     # condition set OR one compound set, chosen with the mode switch.
     |> assign(:filter_mode, :condition)
     |> assign(:selected_condition_ids, MapSet.new())
     |> assign(:selected_compound_ids, MapSet.new())
     |> assign(:conditions_by_category, conditions_by_category(language))
     |> assign(:all_compounds, all_compounds)
     |> assign(:compounds_by_id, Map.new(all_compounds, &{&1.id, &1}))
     |> assign(:compound_query, "")
     |> assign(:compound_results, [])
     |> assign(:page_title, "Foods & Nutrition Database")
     |> assign(
       :page_description,
       "Browse our database of food species with detailed nutrition facts, the research behind them, and the bioactive compounds they carry."
     )}
  end

  @impl true
  def handle_event("search", %{"q" => query}, socket) do
    {:noreply,
     socket
     |> assign(:query, query)
     |> refresh_species()}
  end

  def handle_event("toggle_filters", _params, socket) do
    {:noreply, assign(socket, :show_filters, !socket.assigns.show_filters)}
  end

  def handle_event("set_filter_mode", %{"mode" => mode}, socket) do
    {:noreply,
     socket
     |> assign(:filter_mode, filter_mode(mode))
     |> refresh_species()}
  end

  def handle_event("toggle_condition", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> assign(:selected_condition_ids, toggle_id(socket.assigns.selected_condition_ids, id))
     |> refresh_species()}
  end

  # Multi-select compound search — filter the linked-compound list as the user types,
  # excluding those already picked.
  def handle_event("search_compounds", %{"q" => query}, socket) do
    {:noreply,
     socket
     |> assign(:compound_query, query)
     |> assign(:compound_results, compound_suggestions(socket, query))}
  end

  def handle_event("add_compound", %{"id" => id}, socket) do
    selected = MapSet.put(socket.assigns.selected_compound_ids, String.to_integer(id))

    {:noreply,
     socket
     |> assign(:selected_compound_ids, selected)
     |> assign(:compound_query, "")
     |> assign(:compound_results, [])
     |> refresh_species()}
  end

  def handle_event("remove_compound", %{"id" => id}, socket) do
    selected = MapSet.delete(socket.assigns.selected_compound_ids, String.to_integer(id))

    {:noreply,
     socket
     |> assign(:selected_compound_ids, selected)
     |> refresh_species()}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_condition_ids, MapSet.new())
     |> assign(:selected_compound_ids, MapSet.new())
     |> assign(:compound_query, "")
     |> assign(:compound_results, [])
     |> refresh_species()}
  end

  def handle_event("load_more", _, %{assigns: %{cursor_after: nil}} = socket) do
    {:noreply, socket}
  end

  def handle_event("load_more", _, socket) do
    language = socket.assigns[:current_language] || "en"
    {new_species, cursor_after} = load_page(language, socket.assigns.cursor_after)

    {:noreply,
     socket
     |> assign(:species, socket.assigns.species ++ new_species)
     |> assign(:cursor_after, cursor_after)}
  end

  # Whether the *active* mode has a selection applied.
  def filters_active?(%{filter_mode: :condition} = assigns),
    do: MapSet.size(assigns.selected_condition_ids) > 0

  def filters_active?(%{filter_mode: :compound} = assigns),
    do: MapSet.size(assigns.selected_compound_ids) > 0

  # The compound structs currently selected, name-ordered — for the chip row.
  def selected_compounds(assigns) do
    assigns.selected_compound_ids
    |> Enum.map(&Map.get(assigns.compounds_by_id, &1))
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.name)
  end

  # The URL slug for a species — Greek `display_name` when set, else the English name.
  def species_slug(%{display_name: name}) when is_binary(name),
    do: URI.encode(String.replace(name, " ", "-"))

  def species_slug(%{name: name}), do: String.replace(name, " ", "-")

  # The label shown on a card — the injected Greek name, else the English name.
  def species_label(species), do: Map.get(species, :display_name) || species.name

  # The sub-label under the name — variety when present, else family.
  def species_sublabel(%{variety: variety}) when is_binary(variety) and variety != "",
    do: variety

  def species_sublabel(%{family: family}) when is_binary(family) and family != "", do: family
  def species_sublabel(_), do: nil

  # Styling for a facet filter pill.
  def pill_class(selected?) do
    base = "px-3 py-1 rounded-full text-sm font-medium border transition"

    if selected? do
      "#{base} bg-paprika border-paprika text-white"
    else
      "#{base} border-ink-panel2 text-parchment-dim hover:border-paprika hover:text-parchment"
    end
  end

  ###################################################################### PRIVATE ###############################################################

  defp filter_mode("compound"), do: :compound
  defp filter_mode(_), do: :condition

  defp toggle_id(set, id) do
    id = String.to_integer(id)
    if MapSet.member?(set, id), do: MapSet.delete(set, id), else: MapSet.put(set, id)
  end

  defp compound_suggestions(socket, query) do
    term = String.trim(query)

    if term == "" do
      []
    else
      down = String.downcase(term)
      selected = socket.assigns.selected_compound_ids

      socket.assigns.all_compounds
      |> Enum.filter(fn c ->
        not MapSet.member?(selected, c.id) and String.contains?(String.downcase(c.name), down)
      end)
      |> Enum.take(@compound_suggestions)
    end
  end

  # Recompute the species list from the current query + the *active* mode's facet.
  #
  #   * No facet, blank query → the default paginated feed.
  #   * No facet, text query  → the name search (localized in Greek mode).
  #   * Facet active          → the faceted filter (flat list, no pagination).
  defp refresh_species(socket) do
    language = socket.assigns[:current_language] || "en"
    query = socket.assigns.query
    {condition_ids, compound_ids} = active_facet_ids(socket)

    cond do
      condition_ids == [] and compound_ids == [] and query == "" ->
        {species, cursor_after} = load_page(language, nil)
        assign(socket, species: species, cursor_after: cursor_after)

      condition_ids == [] and compound_ids == [] ->
        assign(socket, species: search_species(query, language), cursor_after: nil)

      true ->
        assign(socket,
          species: filtered_species(condition_ids, compound_ids, query, language),
          cursor_after: nil
        )
    end
  end

  # Only the mode currently in effect contributes a facet — the two are exclusive.
  defp active_facet_ids(%{assigns: %{filter_mode: :condition} = a}),
    do: {MapSet.to_list(a.selected_condition_ids), []}

  defp active_facet_ids(%{assigns: %{filter_mode: :compound} = a}),
    do: {[], MapSet.to_list(a.selected_compound_ids)}

  # Faceted lookup: conditions resolve to their "encourage" compounds AND to species
  # high in an "encourage" nutrient (the two engines are OR-ed inside the condition
  # facet), which — with any directly selected compounds — constrain the species.
  # When conditions are selected but resolve to neither a compound nor a nutrient
  # species, nothing can match, so return [].
  defp filtered_species(condition_ids, compound_ids, query, language) do
    condition_compound_ids = Health.encouraged_compound_ids_for_conditions(condition_ids)
    condition_species_ids = Health.encouraged_species_ids_for_conditions(condition_ids)

    if condition_ids != [] and condition_compound_ids == [] and condition_species_ids == [] do
      []
    else
      Food.filter_species(
        condition_compound_ids: condition_compound_ids,
        condition_species_ids: condition_species_ids,
        compound_ids: compound_ids,
        query: query
      )
      |> localize(language)
    end
  end

  defp search_species(query, "el") do
    SpeciesSearch.search_in_language(query, "el")
    |> Enum.map(fn %{id: id, name: greek_name} ->
      Map.put(Food.get_foundemental_species!(id), :display_name, greek_name)
    end)
  end

  defp search_species(query, _language), do: SpeciesSearch.search(query)

  # Inject the Greek `display_name` from preloaded translations (no-op in English).
  defp localize(species_list, "el") do
    Enum.map(species_list, fn species ->
      case Enum.find(species.translations || [], &(&1.language_name == "el")) do
        nil -> species
        t -> Map.put(species, :display_name, t.name)
      end
    end)
  end

  defp localize(species_list, _language), do: species_list

  # Presentable conditions (those carrying dietary advice) grouped by category.
  defp conditions_by_category(language) do
    Health.list_conditions_for_presentation(language)
    |> Enum.group_by(&(&1.category || "Other"))
    |> Enum.sort_by(fn {category, _} -> category end)
  end

  # In Greek mode: only species with a translation, with display_name injected.
  # In English mode: all species via the standard paginated query.
  defp load_page("el", cursor_after) do
    {entries, next_cursor} = Food.list_species_paginated_translated("el", cursor_after)

    species =
      Enum.map(entries, fn species ->
        greek_name =
          species.translations
          |> Enum.find(&(&1.language_name == "el"))
          |> case do
            nil -> nil
            t -> t.name
          end

        if greek_name, do: Map.put(species, :display_name, greek_name), else: species
      end)

    {species, next_cursor}
  end

  defp load_page(_lang, nil), do: Food.list_species_paginated()
  defp load_page(_lang, cursor_after), do: Food.list_species_paginated(cursor_after)
end
