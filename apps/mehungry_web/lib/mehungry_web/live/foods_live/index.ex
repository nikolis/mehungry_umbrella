defmodule MehungryWeb.FoodsLive.Index do
  use MehungryWeb, :live_view
  alias Mehungry.Food
  alias Mehungry.Food.IngredientSearch
  alias Mehungry.Repo

  @impl true
  def mount(_params, _session, socket) do
    language = socket.assigns[:current_language] || "en"
    {ingredients, cursor_after} = load_page(language, nil)

    {:ok,
     socket
     |> assign(:ingredients, ingredients)
     |> assign(:cursor_after, cursor_after)
     |> assign(:query, "")
     |> assign(:page_title, "Foods & Nutrition Database")
     |> assign(
       :page_description,
       "Browse our complete food and ingredient database with detailed nutrition facts, vitamins, minerals, and macronutrients."
     )}
  end

  @impl true
  def handle_event("search", %{"q" => ""}, socket) do
    language = socket.assigns[:current_language] || "en"
    {ingredients, cursor_after} = load_page(language, nil)

    {:noreply,
     socket
     |> assign(:query, "")
     |> assign(:ingredients, ingredients)
     |> assign(:cursor_after, cursor_after)}
  end

  def handle_event("search", %{"q" => query}, socket) do
    language = socket.assigns[:current_language] || "en"

    ingredients =
      if language == "el" do
        IngredientSearch.search_in_language(query, "el")
        |> Enum.map(fn %{id: id, name: greek_name} ->
          ingredient = Food.get_ingredient_with_category!(id)
          Map.put(ingredient, :display_name, greek_name)
        end)
      else
        IngredientSearch.search(query)
        |> Repo.preload(:category)
      end

    {:noreply,
     socket
     |> assign(:query, query)
     |> assign(:ingredients, ingredients)
     |> assign(:cursor_after, nil)}
  end

  def handle_event("load_more", _, %{assigns: %{cursor_after: nil}} = socket) do
    {:noreply, socket}
  end

  def handle_event("load_more", _, socket) do
    language = socket.assigns[:current_language] || "en"
    {new_ingredients, cursor_after} = load_page(language, socket.assigns.cursor_after)

    {:noreply,
     socket
     |> assign(:ingredients, socket.assigns.ingredients ++ new_ingredients)
     |> assign(:cursor_after, cursor_after)}
  end

  # Returns the URL slug — Greek when a display_name is set, English otherwise.
  def ingredient_slug(%{display_name: name}) when is_binary(name),
    do: URI.encode(String.replace(name, " ", "-"))

  def ingredient_slug(%{search_name: nil}), do: ""
  def ingredient_slug(%{search_name: name}), do: String.replace(name, " ", "-")

  # In Greek mode: only ingredients with a translation, with display_name injected.
  # In English mode: all ingredients via the standard paginated query.
  defp load_page("el", cursor_after) do
    {entries, next_cursor} = Food.list_ingredients_paginated_translated("el", cursor_after)

    ingredients =
      Enum.map(entries, fn ingredient ->
        greek_name =
          ingredient.ingredient_translation
          |> Enum.find(&(&1.language_name == "el"))
          |> case do
            nil -> nil
            t -> t.name
          end

        if greek_name, do: Map.put(ingredient, :display_name, greek_name), else: ingredient
      end)

    {ingredients, next_cursor}
  end

  defp load_page(_lang, nil), do: Food.list_ingredients_paginated()

  defp load_page(_lang, cursor_after),
    do: Food.list_ingredients_paginated(cursor_after)
end
