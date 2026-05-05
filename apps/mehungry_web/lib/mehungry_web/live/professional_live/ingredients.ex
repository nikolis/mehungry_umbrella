defmodule MehungryWeb.ProfessionalLive.Ingredients do
  use MehungryWeb, :live_view

  alias Mehungry.Food

  import Ecto.Changeset

  @types %{
    query: :string,
    categories: {:array, :string},
    search_method: :string
  }

  @params %{
    "query" => "",
    "classes" => nil,
    "search_method" => ""
  }

  @food_classes [
    {"Branded", "Branded"},
    {"FinalFood", "FinalFood"},
    {"Admin created", "Admin created"},
    {"Survey", "Survey"},
    {"Foundation", "Foundation"}
  ]

  defp get_form_changeset(params) do
    changeset =
      {params, @types}
      |> cast(params, Map.keys(@types))
      |> validate_required([:query])
  end

  @impl true
  def mount(_params, _session, socket) do
    {ingredients, cursor_after} = Food.list_ingredients_paginated()

    categories =
      Food.list_categories()

    search_methods = [{"ilike", "ilike"}, {"search", "search"}]

    socket =
      socket
      |> stream(:ingredients, ingredients)
      |> assign(:category, nil)
      |> assign(:food_classes, @food_classes)
      |> assign(:search_methods, search_methods)
      |> assign(:search_method, "ilike")
      |> assign(:query, "")
      |> assign(:ecto_query, nil)
      |> assign(:cursor_after, cursor_after)
      |> assign(:page, 1)
      |> assign(:form, to_form(get_form_changeset(@params), as: :search_form))

    {:ok, socket}
  end

  @impl true
  def handle_event("search_change", %{"search_form" => search_form} = rest, socket) do
    socket = execute_query(search_form, socket)

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_change", %{"_target" => [target]} = vari, socket) do
    value = Map.get(vari, target, nil)

    {:noreply, socket}
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

  def execute_query(form_params, socket) do
    classes = String.split(form_params["classes"], ",")

    {ecto_query, {ingredients, cursor}} =
      case form_params["search_method"] do
        "ilike" ->
          Food.search_ingredient_admin(form_params["query"], classes)

        "search" ->
          Food.search_ingredient_alt_admin(form_params["query"], classes)
      end

    # socket = assign(socket, :query, form_params)
    socket = assign(socket, :ecto_query, ecto_query)

    socket
    |> assign(:cursor_after, cursor)

    stream(socket, :ingredients, ingredients, reset: true)
  end
end
