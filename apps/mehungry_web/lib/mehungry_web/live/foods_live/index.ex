defmodule MehungryWeb.FoodsLive.Index do
  use MehungryWeb, :live_view
  alias Mehungry.Food
  alias Mehungry.Food.SpeciesSearch

  @impl true
  def mount(_params, _session, socket) do
    language = socket.assigns[:current_language] || "en"
    {species, cursor_after} = load_page(language, nil)

    {:ok,
     socket
     |> assign(:species, species)
     |> assign(:language, language)
     |> assign(:cursor_after, cursor_after)
     |> assign(:query, "")
     |> assign(:page_title, gettext("Foods & Nutrition Database"))
     |> assign(
       :page_description,
       gettext(
         "Browse our database of food species with detailed nutrition facts and the research behind them."
       )
     )
     |> assign(:directory, build_directory(language))}
  end

  @impl true
  def handle_event("search", %{"q" => query}, socket) do
    {:noreply,
     socket
     |> assign(:query, query)
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

  # The default feed state: no name search active. Drives both the spotlight card
  # and the crawlable A–Z directory (shown only here).
  def default_browse?(assigns), do: assigns.query == ""

  # Whether to weave the "find a nutritionist" spotlight into the species grid —
  # only in the default browse state and once there are enough cards that it
  # reads as part of the collection, not a lonely banner.
  def spotlight?(assigns), do: default_browse?(assigns) and length(assigns.species) > 8

  # The URL slug for a species — Greek `display_name` when set, else the English
  # name, spaces hyphenated. Raw/unencoded to match `SpeciesDetailLive`'s canonical
  # slug byte-for-byte (the browser percent-encodes any non-ASCII on request), so a
  # card links to the detail page's own canonical URL rather than an encoded variant.
  def species_slug(species), do: Food.species_slug(species_label(species) || "")

  # The label shown on a card — the injected Greek name, else the English name.
  def species_label(species), do: Map.get(species, :display_name) || species.name

  # The sub-label under the name — variety when present, else family.
  def species_sublabel(%{variety: variety}) when is_binary(variety) and variety != "",
    do: variety

  def species_sublabel(%{family: family}) when is_binary(family) and family != "", do: family
  def species_sublabel(_), do: nil

  ###################################################################### PRIVATE ###############################################################

  # Recompute the species list from the current query.
  #
  #   * Blank query → the default paginated feed.
  #   * Text query  → the name search (localized in Greek mode).
  defp refresh_species(socket) do
    language = socket.assigns[:current_language] || "en"
    query = socket.assigns.query

    if query == "" do
      {species, cursor_after} = load_page(language, nil)
      assign(socket, species: species, cursor_after: cursor_after)
    else
      assign(socket, species: search_species(query, language), cursor_after: nil)
    end
  end

  defp search_species(query, "el") do
    hits = SpeciesSearch.search_in_language(query, "el")
    by_id = Food.species_by_ids(Enum.map(hits, & &1.id))

    # Resolve all hits in one query (not an N+1 of get_species!/1), keeping the
    # search ranking order and injecting each hit's Greek name as display_name.
    hits
    |> Enum.map(fn %{id: id, name: greek_name} ->
      case Map.get(by_id, id) do
        nil -> nil
        species -> Map.put(species, :display_name, greek_name)
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp search_species(query, _language), do: SpeciesSearch.search(query)

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

  # ── A–Z directory ──────────────────────────────────────────────────────────
  # Every species as a crawlable link, grouped by first letter. The paginated
  # feed above only renders the first page on the dead render, so without this
  # the ~140 other food pages get no link equity from /foods and rank poorly
  # (deep pages sat at GSC position 30–60). Links use the same canonical slug per
  # locale as `SpeciesDetailLive` (English name for :en, the el translation for
  # :el), so they point at each page's real canonical URL.
  defp build_directory(language) do
    Food.list_species_for_directory()
    |> Enum.map(fn species ->
      el_name =
        case Enum.find(species.translations, &(&1.language_name == "el")) do
          %{name: name} -> name
          _ -> nil
        end

      slug_name = if language == "el" and el_name, do: el_name, else: species.name
      label = if language == "el" and el_name, do: el_name, else: species.name

      %{label: label, path: "/#{language}/foods/#{Food.species_slug(slug_name || "")}"}
    end)
    |> Enum.reject(&(&1.label in [nil, ""]))
    |> Enum.sort_by(&String.downcase(&1.label))
    |> Enum.group_by(&directory_letter(&1.label))
    |> Enum.sort_by(fn {letter, _entries} -> letter end)
  end

  defp directory_letter(label) do
    case label |> String.trim() |> String.first() do
      nil -> "#"
      letter -> String.upcase(letter)
    end
  end
end
