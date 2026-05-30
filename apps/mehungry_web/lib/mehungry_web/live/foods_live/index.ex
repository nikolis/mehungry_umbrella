defmodule MehungryWeb.FoodsLive.Index do
  use MehungryWeb, :live_view
  alias Mehungry.Food
  alias Mehungry.Food.IngredientSearch
  alias Mehungry.Repo

  @impl true
  def mount(_params, _session, socket) do
    {ingredients, cursor_after} = Food.list_ingredients_paginated()

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
    {ingredients, cursor_after} = Food.list_ingredients_paginated()

    {:noreply,
     socket
     |> assign(:query, "")
     |> assign(:ingredients, ingredients)
     |> assign(:cursor_after, cursor_after)}
  end

  def handle_event("search", %{"q" => query}, socket) do
    ingredients =
      IngredientSearch.search(query)
      |> Repo.preload(:category)

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
    {new_ingredients, cursor_after} =
      Food.list_ingredients_paginated(socket.assigns.cursor_after)

    {:noreply,
     socket
     |> assign(:ingredients, socket.assigns.ingredients ++ new_ingredients)
     |> assign(:cursor_after, cursor_after)}
  end

  def ingredient_slug(%{search_name: nil}), do: ""
  def ingredient_slug(%{search_name: name}), do: String.replace(name, " ", "-")
end
