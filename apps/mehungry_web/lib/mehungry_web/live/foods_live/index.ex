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
     |> assign(:cursor_after, cursor_after)
     |> assign(:query, "")
     |> assign(:page_title, "Foods & Nutrition Database")
     |> assign(
       :page_description,
       "Browse our database of food species with detailed nutrition facts, the research behind them, and the bioactive compounds they carry."
     )}
  end

  @impl true
  def handle_event("search", %{"q" => ""}, socket) do
    language = socket.assigns[:current_language] || "en"
    {species, cursor_after} = load_page(language, nil)

    {:noreply,
     socket
     |> assign(:query, "")
     |> assign(:species, species)
     |> assign(:cursor_after, cursor_after)}
  end

  def handle_event("search", %{"q" => query}, socket) do
    language = socket.assigns[:current_language] || "en"

    species =
      if language == "el" do
        SpeciesSearch.search_in_language(query, "el")
        |> Enum.map(fn %{id: id, name: greek_name} ->
          Map.put(Food.get_foundemental_species!(id), :display_name, greek_name)
        end)
      else
        SpeciesSearch.search(query)
      end

    {:noreply,
     socket
     |> assign(:query, query)
     |> assign(:species, species)
     |> assign(:cursor_after, nil)}
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
