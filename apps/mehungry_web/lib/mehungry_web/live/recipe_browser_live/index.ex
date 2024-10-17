defmodule MehungryWeb.RecipeBrowserLive.Index do
  use MehungryWeb, :live_view
  use MehungryWeb.LiveHelpers, :hook_for_update_recipe_details_component
  use MehungryWeb.Presence, :user_tracking

  alias Mehungry.Food
  alias Mehungry.Food.Recipe
  alias Mehungry.Search.RecipeSearchItem
  alias Mehungry.Search
  alias MehungryWeb.ImageProcessing
  alias Mehungry.Accounts
  alias Mehungry.Users
  alias Mehungry.Food.RecipeUtils
  alias Mehungry.Posts
  alias MehungryWeb.RecipeComponents

  @impl true
  def mount(params, session, socket) do
    query_str = Map.get(params, "query", nil)

    user =
      case is_nil(session["user_token"]) do
        true ->
          nil

        false ->
          Accounts.get_user_by_session_token(session["user_token"])
      end

    # changeset =
    # %RecipeSearchItem{query_string: nil}
    # |> Search.change_recipe_search_item(%{query_string: query_str})

    {user_profile, user_follows, user_recipes} = Accounts.get_user_essentials(user)

    {query, {recipes, cursor_after}} =
      case query_str do
        nil ->
          {query_str, list_recipes()}

        qr ->
          Food.search_recipe(qr)
      end

    {:ok,
     socket
     |> assign(:cursor_after, cursor_after)
     |> assign(:recipe, nil)
     |> assign(
       :not_empty,
       if length(recipes) > 0 do
         true
       else
         false
       end
     )
     |> assign(:current_user_recipes, user_recipes)
     |> assign(:current_user_follows, user_follows)
     |> assign(:current_user_profile, user_profile)
     |> assign(:current_user, user)
     |> assign(:query_string, query_str)
     |> assign(:page, 1)
     |> assign(:invocations, 0)
     |> assign(:counter, 1)
     |> assign(:query, query)
     |> assign(:must_be_loged_in, nil)
     |> assign(:reply, nil)
     |> assign_recipe_search()}
  end

  def assign_recipe_search(socket) do
    socket
    |> assign(:recipe_search_item, %RecipeSearchItem{query_string: "asdfafsdf"})
  end

  @impl true
  def handle_info({MehungryWeb.Onboarding.FormComponent, "profile-saved"}, socket) do
    user_profile = Accounts.get_user_profile_by_user_id(socket.assigns.current_user.id)

    {:noreply,
     socket
     |> assign(:user_profile, user_profile)}
  end

  def assign_changeset(%{assigns: %{recipe_search_item: recipe_search_item}} = socket) do
    result =
      socket
      |> assign(:changeset, Search.change_recipe_search_item(recipe_search_item))

    result
  end

  @impl true
  def handle_event("review", %{"id" => id, "points" => points}, socket) do
    # %{"user_id" => [{recipe_id, grade}]}
    # To be fixed I need to use a map instead if I want to keep a single grade for the a particular recipe
    users = Cachex.get(:users, "data")
    user_id = socket.assigns.current_user.id

    _new_content =
      case users do
        {:ok, nil} ->
          %{to_string(user_id) => [{id, points}]}

        {:ok, user_content} ->
          case Map.get(user_content, to_string(user_id)) do
            nil ->
              Map.put(user_content, to_string(user_id), [{id, points}])

            content ->
              new_list = content ++ [{id, points}]
              Map.put(user_content, to_string(user_id), new_list)
          end
      end

    {:noreply, assign(socket, :recipes, list_recipes())}
  end

  @impl true
  def handle_event("close-modal", _thing, socket) do
    {:noreply, push_patch(socket, to: "/browse")}
  end

  @impl true
  def handle_event("keep_browsing", _thing, socket) do
    {:noreply, assign(socket, :must_be_loged_in, nil)}
  end

  @impl true
  def handle_event(
        "save_user_recipe_dets",
        %{"recipe_id" => recipe_id, "dom_id" => _dom_id},
        socket
      ) do
    case is_nil(socket.assigns.current_user) do
      true ->
        socket = assign(socket, :must_be_loged_in, 1)
        {:noreply, socket}

      false ->
        {recipe_id, _ignore} = Integer.parse(recipe_id)
        toggle_user_saved_recipes(socket, recipe_id)
        user_recipes = Users.list_user_saved_recipes(socket.assigns.current_user)
        user_recipes = Enum.map(user_recipes, fn x -> x.recipe_id end)
        socket = assign(socket, :user_recipes, user_recipes)
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("save_user_recipe", %{"recipe_id" => recipe_id, "dom_id" => _dom_id}, socket) do
    case is_nil(socket.assigns.current_user) do
      true ->
        socket = assign(socket, :must_be_loged_in, 1)
        {:noreply, socket}

      false ->
        {recipe_id, _ignore} = Integer.parse(recipe_id)
        toggle_user_saved_recipes(socket, recipe_id)

        user_recipes =
          Users.list_user_saved_recipes(socket.assigns.current_user)
          |> Enum.map(fn x -> x.recipe_id end)

        socket = assign(socket, :user_recipes, user_recipes)
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("load-more", _, socket) do
    cursor_after = Map.get(socket.assigns, :cursor_after)

    {recipes, cursor_after} =
      Food.list_recipes(cursor_after, Map.get(socket.assigns, :query, nil))

    # all_recipes  = socket.assigns.recipes ++ recipes

    {:noreply,
     socket
     |> assign(:cursor_after, cursor_after)
     |> assign(:page, socket.assigns.page + 1)
     |> stream(:recipes, recipes)}
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
     |> assign(:search_changeset, changeset)}
  end

  def handle_event("search", %{"recipe_search_item" => %{"query_string" => query_string}}, socket) do
    # There is a problem with getting the results of the search because it does not work properly with the phx-update'Stream' on the other hand
    # The listing of recipes suppose to use phx-update Stream As more efficient
    case String.length(query_string) == 0 do
      true ->
        {:noreply, Phoenix.LiveView.push_navigate(socket, to: "/browse")}

      false ->
        {:noreply, Phoenix.LiveView.push_navigate(socket, to: "/search/" <> query_string)}
    end
  end

  def handle_event(
        "search",
        %{"recipe_search_item" => recipe_search_item_params},
        %{assigns: %{recipe_search_item: recipe_search_item}} = socket
      ) do
    update_result =
      recipe_search_item
      |> Search.update_recipe_search_item(recipe_search_item_params)

    changeset =
      recipe_search_item
      |> Search.change_recipe_search_item(recipe_search_item_params)

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
         |> stream(:recipes, recipes, reset: true)
         |> assign(:changeset, changeset)}
    end
  end

  def toggle_user_saved_recipes(socket, recipe_id) do
    case is_nil(socket.assigns.current_user) do
      true ->
        assign(socket, :must_be_loged_in, 1)

      false ->
        case Enum.any?(socket.assigns.current_user_recipes, fn x -> x == recipe_id end) do
          true ->
            Users.remove_user_saved_recipe(socket.assigns.current_user.id, recipe_id)

          false ->
            Users.save_user_recipe(socket.assigns.current_user.id, recipe_id)
        end
    end
  end

  @impl true
  def handle_params(params, uri, socket) do
    socket = assign(socket, :path, uri)

    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, %{"query" => query_str} = _params) do
    maybe_track_user(%{query: query_str}, socket)
    user = socket.assigns.current_user

    user_profile =
      case is_nil(user) do
        true ->
          nil

        false ->
          Accounts.get_user_profile_by_user_id(user.id)
      end

    # changeset =
    # %RecipeSearchItem{query_string: nil}
    # |> Search.change_recipe_search_item(%{query_string: query_str})

    {query, {recipes, cursor_after}} =
      case query_str do
        nil ->
          {query_str, list_recipes()}

        qr ->
          Food.search_recipe(qr)
      end

    user_recipes =
      case is_nil(user) do
        true ->
          []

        false ->
          Users.list_user_saved_recipes(user)
          |> Enum.map(fn x -> x.recipe_id end)
      end

    stream(socket, :recipes, recipes)
    |> assign(:cursor_after, cursor_after)
    |> assign(:recipe, nil)
    |> assign(
      :not_empty,
      if length(recipes) > 0 do
        true
      else
        false
      end
    )
    |> assign(:user_recipes, user_recipes)
    |> assign(:page, 1)
    |> assign(:query_string, query_str)
    |> assign(:search_changeset, nil)
    |> assign(:user_profile, user_profile)
    |> assign(:page_title, "search for recipe  " <> query_str)
    |> assign(:query, %{title: query})
  end

  defp apply_action(socket, :index, _) do
    user = socket.assigns.current_user
    query_str = ""

    user_profile =
      case is_nil(user) do
        true ->
          nil

        false ->
          Accounts.get_user_profile_by_user_id(user.id)
      end

    # changeset =
    # %RecipeSearchItem{query_string: nil}
    # |> Search.change_recipe_search_item(%{query_string: query_str})

    {query, {recipes, cursor_after}} =
      case query_str do
        nil ->
          {query_str, list_recipes()}

        qr ->
          Food.search_recipe(qr)
      end

    user_recipes =
      case is_nil(user) do
        true ->
          []

        false ->
          Users.list_user_saved_recipes(user)
          |> Enum.map(fn x -> x.recipe_id end)
      end

    maybe_track_user(%{query: ""}, socket)

    socket =
      stream(socket, :recipes, recipes)
      |> assign(:cursor_after, cursor_after)
      |> assign(:recipe, nil)
      |> assign(
        :not_empty,
        if length(recipes) > 0 do
          true
        else
          false
        end
      )
      |> assign(:user_recipes, user_recipes)
      |> assign(:page, 1)
      |> assign(:page_title, "Browse food recipes")
      |> assign(:query_string, "")
      |> assign(:search_changeset, nil)
      |> assign(:user_profile, user_profile)
      |> assign(:query, query)

    assign(socket, :search_changeset, nil)
    |> assign(:query_string, nil)
  end

  defp apply_action(socket, :show_recipe, %{"id" => id}) do
    recipe = Food.get_recipe!(id)
    Posts.subscribe_to_recipe(%{recipe_id: id})

    query_str = ""

    {_query, {recipes, _cursor_after}} =
      case query_str do
        nil ->
          {query_str, list_recipes()}

        qr ->
          Food.search_recipe(qr)
      end

    {primaries_length, nutrients} = RecipeUtils.get_nutrients(recipe)
    user = socket.assigns.current_user

    user_recipes =
      case is_nil(user) do
        true ->
          []

        false ->
          Users.list_user_saved_recipes(user)
          |> Enum.map(fn x -> x.recipe_id end)
      end

    socket =
      socket
      |> assign(:nutrients, nutrients)
      |> assign(:primary_size, primaries_length)
      |> assign(:recipe, recipe)
      |> assign(:page_title, recipe.title <> " Instructions and nutrition facts")
      |> stream(:recipes, recipes)
      |> assign(:user_recipes, user_recipes)

    maybe_track_user(%{page: "browser", type: :show_recipe, recipe: recipe}, socket)
    socket
  end

  defp apply_action(socket, :show, %{"id" => id}) do
    recipe = Food.get_recipe!(id)
    {primaries_length, nutrients} = RecipeUtils.get_nutrients(recipe)
    maybe_track_user(recipe, socket)

    # user = socket.assigns.user
    query_str = ""

    # user_profile =
    # case is_nil(user) do
    #  true ->
    #   nil

    # false ->
    #  Accounts.get_user_profile_by_user_id(user.id)
    # end

    # changeset =
    # %RecipeSearchItem{query_string: nil}
    # |> Search.change_recipe_search_item(%{query_string: query_str})

    {_query, {recipes, cursor_after}} =
      case query_str do
        nil ->
          {query_str, list_recipes()}

        qr ->
          Food.search_recipe(qr)
      end

    # user_recipes =
    # case is_nil(user) do
    #  true ->
    #   []

    # false ->
    #  Users.list_user_saved_recipes(user)
    # |> Enum.map(fn x -> x.recipe_id end)
    # end

    socket
    |> assign(:nutrients, nutrients)
    |> assign(:primary_size, primaries_length)
    |> assign(:recipe, recipe)
    |> assign(:query_string, nil)
    |> stream(:recipes, recipes)
    |> assign(:cursor_after, cursor_after)
    |> assign(:page_title, %{
      title: recipe.title,
      img: recipe.image_url,
      id: Integer.to_string(recipe.id)
    })
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
