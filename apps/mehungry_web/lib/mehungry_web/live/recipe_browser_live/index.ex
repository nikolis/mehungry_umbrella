defmodule MehungryWeb.RecipeBrowseLive.Index do
  use MehungryWeb, :live_view

  alias Mehungry.Food
  alias Mehungry.Food.Recipe
  alias Mehungry.Search.RecipeSearchItem
  alias Mehungry.Search
  alias MehungryWeb.Presence
  alias Mehungry.Accounts
  alias MehungryWeb.ImageProcessing

  @user_id 5

  @impl true
  def mount(_params, _session, socket) do
    IO.inspect("Mount")

    {:ok,
     assign(socket, :recipes, list_recipes())
     |> assign_recipe_search()
     |> assign_changeset()}
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
  def handle_event("validate", %{"recipe_search_item" => search_item} = thing, socket) do
    IO.inspect(thing, label: "Thing")
    IO.inspect("General handle Locally though")
    {:noreply, socket}
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

    IO.inspect("THe local impl", label: "The")

    {:noreply,
     socket
     |> assign(:changeset, changeset)}
  end

  def handle_event(any, _, socket) do
    IO.inspect(any, label: "From within")

    IO.inspect(
      "----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------"
    )

    {:noreply, socket}
  end

  def handle_event("search", %{"recipe_search_item" => %{"query_string" => query_string}}, socket) do
    IO.inspect("General handle Buttt locally here")
    IO.inspect(query_string, label: "Query String")
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
  def handle_params(params, _url, socket) do
    maybe_track_user(nil, socket)
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  def maybe_track_user(
        product,
        %{assigns: %{live_action: :index, current_user: current_user}} = socket
      ) do
    if connected?(socket) do
      Presence.track_user(self(), "recipe_browser_live", current_user.email)
    end
  end

  def maybe_track_user(product, socket), do: nil

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing Categories")
    |> assign(:category, nil)
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

    new_content =
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
    Food.list_recipes()
    |> Enum.map(fn recipe ->
      return = ImageProcessing.resize(recipe.image_url, 100, 100)
      %Recipe{recipe | recipe_image_remote: return}
    end)
  end
end
