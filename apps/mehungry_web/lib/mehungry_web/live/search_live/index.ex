defmodule MehungryWeb.SearchLive.Index do
  use MehungryWeb, :live_component

  alias Mehungry.Search.RecipeSearchItem
  alias Mehungry.Food.Recipe
  alias Mehungry.Food
  alias Mehungry.Accounts
  alias Mehungry.Search
  alias MehungryWeb.ImageProcessing

  @impl true
  def update(assigns, socket) do
    query_string = Map.get(assigns, :query_string, nil)

    {:ok,
     socket
     |> assign_recipe_search()
     |> assign(:query_string, query_string)
     |> assign(assigns)
     |> assign_changeset()}
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

  def mount(_params, session, socket) do
    user = Accounts.get_user_by_session_token(session["user_token"])

    {:ok,
     socket
     |> assign(:recipes, list_recipes())
     |> assign_recipe_search()
     |> assign(:user, user)
     |> assign_changeset()}
  end

  def assign_recipe_search(socket) do
    socket
    |> assign(:recipe_search_item, %RecipeSearchItem{})
  end

  def assign_changeset(%{assigns: %{recipe_search_item: recipe_search_item}} = socket) do
    socket
    |> assign(:search_changeset, Search.change_recipe_search_item(recipe_search_item))
  end

  defp apply_action(socket, :index, _params) do
    socket
  end

  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp list_recipes do
    Food.list_recipes(nil)
    |> Enum.map(fn recipe ->
      return = ImageProcessing.resize(recipe.image_url, 100, 100)
      %Recipe{recipe | recipe_image_remote: return}
    end)
  end
end
