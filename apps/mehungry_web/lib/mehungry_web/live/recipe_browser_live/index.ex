defmodule MehungryWeb.RecipeBrowseLive.Index do
  use MehungryWeb, :live_view

  alias Mehungry.Food
  alias Mehungry.Food.Recipe
  alias Mehungry.Search.RecipeSearchItem
  alias Mehungry.Search
  alias MehungryWeb.Presence
  alias MehungryWeb.ImageProcessing

  alias MehungryWeb.RecipeBrowseLive.Modal

  @user_id 5

  @impl true
  def mount(_params, _session, socket) do
    {recipes, cursor_after} = list_recipes()

    {:ok,
     assign(socket, :recipes, recipes)
     |> assign(:cursor_after, cursor_after)
     |> assign(:recipe, nil)
     |> assign(:page, 1)
     |> assign(:counter, 1)
     |> assign_recipe_search()
     |> assign_changeset()}
  end

  def is_open(action, url, invocations) do
    result = String.split(url, "/")

    case action do
      :show ->
        "is-open"

      _ ->
        if length(result) >= 5 do
          "is-closing"
        else
          if invocations > 1 do
            "is-closing"
          else
            "is-closed"
          end
        end
    end
  end

  def assign_recipe_search(socket) do
    socket
    |> assign(:recipe_search_item, %RecipeSearchItem{})
  end

  def assign_changeset(%{assigns: %{recipe_search_item: recipe_search_item}} = socket) do
    result =
      socket
      |> assign(:changeset, Search.change_recipe_search_item(recipe_search_item))

    result
  end

  @impl true
  def handle_event("close-modal", _thing, socket) do
    Process.sleep(500)
    {:noreply, push_patch(socket, to: "/browse")}
  end

  @impl true
  def handle_event("load-more", _, socket) do
    cursor_after = Map.get(socket.assigns, :cursor_after)

    {recipes, cursor_after} = Food.list_recipes(cursor_after)

    # all_recipes  = socket.assigns.recipes ++ recipes

    {:noreply,
     socket
     |> assign(:cursor_after, cursor_after)
     |> assign(:page, socket.assigns.page + 1)
     |> assign(:recipes, recipes)}
  end

  @impl true
  def handle_event(
        "validate",
        %{"recipe_search_item" => recipe_search_item_params},
        %{assigns: %{recipe_search_item: recipe_search_item}} = socket
      ) do
    changeset =
      recipe_search_item
      |> Search.change_recipe_search_item(recipe_search_item_params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:changeset, changeset)}
  end

  @impl true
  def handle_event("recipe_details_nav", %{"recipe_id" => recipe_id}, socket) do
    {:noreply, push_patch(socket, to: "/browse/" <> recipe_id)}
  end

  def handle_event("search", %{"recipe_search_item" => %{"query_string" => query_string}}, socket) do
    {:noreply, Phoenix.LiveView.push_navigate(socket, to: "/browse")}
  end

  def handle_event(
        "search",
        %{"recipe_search_item" => recipe_search_item_params},
        %{assigns: %{recipe_search_item: recipe_search_item}} = socket
      ) do
    update_result =
      recipe_search_item
      |> Search.update_recipe_search_item(recipe_search_item_params)

    case update_result do
      {:error, %Ecto.Changeset{} = changeset} ->
        changeset = Map.put(changeset, :action, :validate)

        {:noreply,
         socket
         |> assign(:changeset, changeset)}

      {:ok, %RecipeSearchItem{} = recipe_search_item} ->
        recipes = Search.search_recipe(recipe_search_item.query_string)

        {:noreply,
         socket
         |> assign(recipes: recipes)}
    end
  end

  @impl true
  def handle_params(params, uri, socket) do
    maybe_track_user(nil, socket)
    socket = assign(socket, :path, uri)

    socket =
      assign(
        socket,
        :invocations,
        case Map.get(socket.assigns, :invocations) do
          nil ->
            1

          x ->
            x + 1
        end
      )

    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  def maybe_track_user(
        _product,
        %{assigns: %{live_action: :index, current_user: current_user}} = socket
      ) do
    if connected?(socket) do
      Presence.track_user(self(), "recipe_browser_live", current_user.email)
    end
  end

  def maybe_track_user(_product, _socket), do: nil

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing Categories")
    |> assign(:category, nil)
    |> assign(:recipe, nil)
  end

  defp apply_action(socket, :show, %{"id" => id}) do
    socket
    |> assign(:page_title, "Recipe Details")
    |> assign(:recipe, Food.get_recipe!(id))
  end

  @impl true
  def handle_event("review", %{"id" => id, "points" => points}, socket) do
    # %{"user_id" => [{recipe_id, grade}]}
    # To be fixed I need to use a map instead if I want to keep a single grade for the a particular recipe
    users = Cachex.get(:users, "data")

    _new_content =
      case users do
        {:ok, nil} ->
          %{to_string(@user_id) => [{id, points}]}

        {:ok, user_content} ->
          case Map.get(user_content, to_string(@user_id)) do
            nil ->
              Map.put(user_content, to_string(@user_id), [{id, points}])

            content ->
              new_list = content ++ [{id, points}]
              Map.put(user_content, to_string(@user_id), new_list)
          end
      end

    # case Cachex.put(:users, "data", new_content) do
    # {:ok, true} ->

    # {errorm, reason} ->
    # end

    {:noreply, assign(socket, :recipes, list_recipes())}
  end

  defp list_recipes do
    {result, cursor_after} = Food.list_recipes(nil)

    result =
      Enum.map(result, fn recipe ->
        return = ImageProcessing.resize(recipe.image_url, 100, 100)
        %Recipe{recipe | recipe_image_remote: return}
      end)

    {result, cursor_after}
  end
end
