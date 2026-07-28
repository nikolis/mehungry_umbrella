defmodule MehungryWeb.ProfessionalLive.Ingredients do
  use MehungryWeb, :live_view

  require Logger

  alias Mehungry.Food
  alias Mehungry.IngredientTranslationWorker

  import Ecto.Changeset

  # `classes`/`data_types` are stored as the comma-joined strings the filter
  # SelectComponents write into their hidden inputs, so the form can carry them
  # back across re-renders (otherwise LiveView patches the hidden inputs empty
  # and the filters silently drop).
  @types %{
    query: :string,
    classes: :string,
    data_types: :string,
    search_method: :string
  }

  @params %{
    "query" => "",
    "classes" => nil,
    "data_types" => nil,
    "search_method" => ""
  }

  defp get_form_changeset(params) do
    {params, @types}
    |> cast(params, Map.keys(@types))
    |> validate_required([:query])
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Mehungry.PubSub, Food.branded_delete_topic())
    end

    {ingredients, cursor_after} = Food.list_ingredients_paginated()

    _categories = Food.list_categories()
    search_methods = [{"ilike", "ilike"}, {"search", "search"}]
    translation_stats = build_translation_stats()
    food_classes = Enum.map(Food.list_distinct_food_classes(), &{&1, &1})
    data_types = Enum.map(Food.list_distinct_data_types(), &{&1, &1})

    socket =
      socket
      |> stream(:ingredients, ingredients)
      |> assign(:category, nil)
      |> assign(:food_classes, food_classes)
      |> assign(:data_types, data_types)
      |> assign(:search_methods, search_methods)
      |> assign(:search_method, "ilike")
      |> assign(:query, "")
      |> assign(:ecto_query, nil)
      |> assign(:cursor_after, cursor_after)
      |> assign(:page, 1)
      |> assign(:total_count, nil)
      |> assign(:translation_stats, translation_stats)
      |> assign(:search_language, socket.assigns[:current_language] || "en")
      |> assign(:branded_deleting, false)
      |> assign(:form, to_form(get_form_changeset(@params), as: :search_form))

    {:ok, socket}
  end

  @impl true
  def handle_event("search_change", %{"search_form" => search_form} = _rest, socket) do
    socket = execute_query(search_form, socket)

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_change", %{"_target" => [target]} = vari, socket) do
    _value = Map.get(vari, target, nil)

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

  @impl true
  def handle_event("set_search_language", %{"lang" => lang}, socket)
      when lang in ["en", "el"] do
    {:noreply, assign(socket, :search_language, lang)}
  end

  @impl true
  def handle_event("delete_without_nutrients", _params, socket) do
    {:ok, {ingredient_count, recipe_count}} = Food.delete_ingredients_without_nutrients()

    socket =
      socket
      |> put_flash(
        :info,
        "Deleted #{ingredient_count} ingredient(s) and #{recipe_count} recipe(s) with no nutrients."
      )
      |> push_navigate(to: ~p"/professional/ingredients")

    {:noreply, socket}
  end

  @impl true
  def handle_event("delete_branded", _params, socket) do
    Logger.info(
      "[delete_branded] enqueue requested by user #{inspect(socket.assigns[:current_user] && socket.assigns.current_user.id)}"
    )

    socket =
      case Mehungry.ObanWorkers.BrandedIngredientDeleteWorker.enqueue() do
        {:ok, _job} ->
          socket
          |> assign(:branded_deleting, true)
          |> put_flash(
            :info,
            "USDA branded deletion started in the background. This can take a while — you'll be notified here when it finishes."
          )

        {:error, reason} ->
          Logger.error("[delete_branded] enqueue failed: #{inspect(reason)}")
          put_flash(socket, :error, "Could not start deletion: #{inspect(reason)}")
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("enqueue_translation", _params, socket) do
    %{} |> IngredientTranslationWorker.new() |> Oban.insert!()
    translation_stats = build_translation_stats()

    socket =
      socket
      |> assign(:translation_stats, translation_stats)
      |> put_flash(
        :info,
        "Greek translation job enqueued. Oban will process it in the background."
      )

    {:noreply, socket}
  end

  # Progress broadcasts from BrandedIngredientDeleteWorker (see
  # Food.branded_delete_topic/0). Any admin viewing this page — including the one
  # who triggered it — reacts to the same events.
  @impl true
  def handle_info({:branded_delete, :started}, socket) do
    {:noreply, assign(socket, :branded_deleting, true)}
  end

  @impl true
  def handle_info({:branded_delete, {:completed, {ingredient_count, recipe_count}}}, socket) do
    socket =
      socket
      |> assign(:branded_deleting, false)
      |> put_flash(
        :info,
        "Deleted #{ingredient_count} USDA branded ingredient(s) and #{recipe_count} recipe(s)."
      )
      |> push_navigate(to: ~p"/professional/ingredients")

    {:noreply, socket}
  end

  @impl true
  def handle_info({:branded_delete, {:failed, reason}}, socket) do
    socket =
      socket
      |> assign(:branded_deleting, false)
      |> put_flash(:error, "USDA branded deletion failed: #{inspect(reason)}")

    {:noreply, socket}
  end

  defp build_translation_stats, do: Food.ingredient_translation_stats()

  def execute_query(form_params, socket) do
    classes = String.split(form_params["classes"] || "", ",")
    data_types = String.split(form_params["data_types"] || "", ",")
    query = form_params["query"]

    {ecto_query, {ingredients, cursor}, total_count} =
      case socket.assigns.search_language do
        "el" ->
          Food.search_ingredient_admin_translated(query, "el", classes, data_types)

        _ ->
          case form_params["search_method"] do
            "search" -> Food.search_ingredient_alt_admin(query, classes, data_types)
            _ -> Food.search_ingredient_admin(query, classes, data_types)
          end
      end

    socket
    |> assign(:ecto_query, ecto_query)
    |> assign(:cursor_after, cursor)
    |> assign(:total_count, total_count)
    |> assign(:search_method, form_params["search_method"] || socket.assigns.search_method)
    # Re-render the form from the submitted params so the filter hidden inputs
    # (and their chips) keep their selected values across this re-render.
    |> assign(:form, to_form(get_form_changeset(form_params), as: :search_form))
    |> stream(:ingredients, ingredients, reset: true)
  end
end
