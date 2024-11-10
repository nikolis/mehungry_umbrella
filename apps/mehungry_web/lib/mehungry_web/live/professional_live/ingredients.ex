defmodule MehungryWeb.ProfessionalLive.Ingredients do
  use MehungryWeb, :live_view

  alias Mehungry.Food

  @topic "user_activity"
  def mount(_params, _session, socket) do
    {ingredients, cursor_after} = Food.list_ingredients_paginated()

    categories =
      Food.list_categories()
      |> Enum.map(fn x -> {x.name, x.id} end)

    search_methods = [{"ilike", "ilike"}, {"search", "search"}]

    socket =
      socket
      |> stream(:ingredients, [])
      |> assign(:category, nil)
      |> assign(:categories, categories)
      |> assign(:search_methods, search_methods)
      |> assign(:search_method, "ilike")
      |> assign(:query, "")
      |> assign(:ecto_query, nil)
      |> assign(:cursor_after, cursor_after)
      |> assign(:page, 1)

    {:ok, socket}
  end

  @impl true
  def handle_event("filter_change", %{"_target" => [target]} = vari, socket) do
    value = Map.get(vari, target, nil)
    socket = set_value(%{target => value}, socket)

    {:noreply, socket}
  end

  def set_value(%{"search_method" => search_method}, socket) do
    socket = assign(socket, :search_method, search_method)
    execute_query(socket.assigns.query, socket)
  end

  def set_value(%{"category" => category}, socket) do
    assign(socket, :category, category)
  end

  def set_value(%{"query" => query}, socket) do
  
    execute_query(query, socket)
  end


  def execute_query(query, socket) do 
    {ecto_query, {ingredients, cursor}} =  
    case socket.assigns.search_method do 
      "ilike" ->
        Food.search_ingredient_admin(query)
      "search" ->
        Food.search_ingredient_alt_admin(query)
    end 
    socket = assign(socket, :query, query)
    socket = assign(socket, :ecto_query, ecto_query) 
    socket
    |> assign(:cursor_after, cursor)

    socket = stream(socket, :ingredients, ingredients, reset: true)

  end


  @impl true
  def handle_event("load-more", _, socket) do
    cursor_after = Map.get(socket.assigns, :cursor_after)

    {ingredients, cursor_after} =
      Food.list_ingredients_paginated(cursor_after, socket.assigns.ecto_query)

    # all_recipes  = socket.assigns.recipes ++ recipes

    {:noreply,
     socket
     |> assign(:cursor_after, cursor_after)
     |> assign(:page, socket.assigns.page + 1)
     |> stream(:ingredients, ingredients)}
  end
end
