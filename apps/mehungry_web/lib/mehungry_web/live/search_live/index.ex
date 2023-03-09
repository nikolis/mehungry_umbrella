defmodule MehungryWeb.SearchLive.Index do
  use MehungryWeb, :live_component

  import Ecto

  alias Mehungry.Inventory.BasketParams
  alias Mehungry.Inventory
  alias Mehungry.Inventory.ShoppingBasket
  alias Mehungry.Search.RecipeSearchItem
  alias Mehungry.Food.Recipe
  alias Mehungry.Accounts
  alias Mehungry.History
  alias Mehungry.Search

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign_recipe_search()
     |> assign_changeset()}
  end

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
    |> assign(:changeset, Search.change_recipe_search_item(recipe_search_item))
  end

  defp apply_action(socket, :index, _params) do
    socket
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  def handle_event("delete_basket", %{"id" => basket_id}, socket) do
    bs = Inventory.get_shopping_basket!(basket_id)
    Inventory.delete_shopping_basket(bs)

    {:noreply,
     socket
     |> assign(:shopping_basket, nil)}
  end

  defp list_recipes do
    Food.list_recipes()
    |> Enum.map(fn recipe ->
      return = ImageProcessing.resize(recipe.image_url, 100, 100)
      %Recipe{recipe | recipe_image_remote: return}
    end)
  end
end
