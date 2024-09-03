defmodule MehungryWeb.RecipeBrowseLive.Index do
  use MehungryWeb, :live_view

  alias Mehungry.Food
  alias Mehungry.Food.Recipe
  alias Mehungry.Search.RecipeSearchItem
  alias Mehungry.Search
  alias MehungryWeb.Presence
  alias MehungryWeb.ImageProcessing
  alias Mehungry.Accounts
  alias Mehungry.Users
  alias Mehungry.Food.RecipeUtils

  alias MehungryWeb.CommonComponents.RecipeComponents

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

    user_profile =
      case is_nil(user) do
        true ->
          nil

        false ->
          Accounts.get_user_profile_by_user_id(user.id)
      end

    #changeset =
      #%RecipeSearchItem{query_string: nil}
      #|> Search.change_recipe_search_item(%{query_string: query_str})

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
     |> assign(:user_recipes, user_recipes)
     |> assign(:page, 1)
     |> assign(:invocations, 0)
     |> assign(:counter, 1)
     |> assign(:user_profile, user_profile)
     |> assign(:query, query)
     |> assign(:must_be_loged_in, nil)
     |> assign(:user, user)
     |> assign_recipe_search()}
  end

  def assign_recipe_search(socket) do
    socket
    |> assign(:recipe_search_item, %RecipeSearchItem{query_string: "asdfafsdf"})
  end

  @impl true
  def handle_info({MehungryWeb.Onboarding.FormComponent, "profile-saved"}, socket) do
    user_profile = Accounts.get_user_profile_by_user_id(socket.assigns.user.id)

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
    user_id = socket.assigns.user.id

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
    case is_nil(socket.assigns.user) do
      true ->
        socket = assign(socket, :must_be_loged_in, 1)
        {:noreply, socket}

      false ->
        {recipe_id, _ignore} = Integer.parse(recipe_id)
        toggle_user_saved_recipes(socket, recipe_id)
        user_recipes = Users.list_user_saved_recipes(socket.assigns.user)
        user_recipes = Enum.map(user_recipes, fn x -> x.recipe_id end)
        # socket = stream_delete(socket, :recipes, recipe)
        # socket = stream_insert(socket, :recipes, recipe)
        socket = assign(socket, :user_recipes, user_recipes)
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("save_user_recipe", %{"recipe_id" => recipe_id, "dom_id" => _dom_id}, socket) do
    case is_nil(socket.assigns.user) do
      true ->
        socket = assign(socket, :must_be_loged_in, 1)
        {:noreply, socket}

      false ->
        {recipe_id, _ignore} = Integer.parse(recipe_id)
        toggle_user_saved_recipes(socket, recipe_id)
        Users.list_user_saved_recipes(socket.assigns.user)
        |> Enum.map(fn x -> x.recipe_id end)
        user_recipes = 
          Users.list_user_saved_recipes(socket.assigns.user)
          |> Enum.map(fn x -> x.recipe_id end)
        socket = assign(socket, :user_recipes, user_recipes)
        {:noreply, push_patch(socket, to: "/browse")}
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
  def handle_event("recipe_details_nav", %{"recipe_id" => recipe_id}, socket) do
    socket = assign(socket, :invocations, 0)
    {:noreply, push_patch(socket, to: "/browse/" <> recipe_id)}
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
    case is_nil(socket.assigns.user) do
      true ->
        assign(socket, :must_be_loged_in, 1)

      false ->
        case Enum.any?(socket.assigns.user_recipes, fn x -> x == recipe_id end) do
          true ->
            Users.remove_user_saved_recipe(socket.assigns.user.id, recipe_id)

          false ->
            Users.save_user_recipe(socket.assigns.user.id, recipe_id)
        end
    end
  end

  @impl true
  def handle_params(params, uri, socket) do
    maybe_track_user(nil, socket)
    socket = assign(socket, :path, uri)

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

  defp apply_action(socket, :index, %{"query" => query_str} = _params) do
    user = socket.assigns.user

    user_profile =
      case is_nil(user) do
        true ->
          nil

        false ->
          Accounts.get_user_profile_by_user_id(user.id)
      end

    #changeset =
     # %RecipeSearchItem{query_string: nil}
      #|> Search.change_recipe_search_item(%{query_string: query_str})

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
    |> assign(:page_title, query_str)
    |> assign(:query, %{title: query})
  end

  defp apply_action(socket, :index, _) do
    user = socket.assigns.user
    query_str = ""

    user_profile =
      case is_nil(user) do
        true ->
          nil

        false ->
          Accounts.get_user_profile_by_user_id(user.id)
      end

    #changeset =
     # %RecipeSearchItem{query_string: nil}
      #|> Search.change_recipe_search_item(%{query_string: query_str})

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
      |> assign(:query_string, "")
      |> assign(:search_changeset, nil)
      |> assign(:user_profile, user_profile)
      |> assign(:query, query)

    assign(socket, :search_changeset, nil)
    |> assign(:query_string, nil)
  end

  defp apply_action(socket, :show, %{"id" => id}) do
    recipe = Food.get_recipe!(id)

    recipe_nutrients =
      RecipeUtils.calculate_recipe_nutrition_value(recipe)

    rest =
      Enum.filter(recipe_nutrients.flat_recipe_nutrients, fn x ->
        Float.round(x.amount, 3) != 0
      end)

    {mufa_all, rest} = get_nutrient_category(rest, "MUFA", "Fatty acids, total monounsaturated")
    {pufa_all, rest} = get_nutrient_category(rest, "PUFA", "Fatty acids, total polyunsaturated")
    {sfa_all, rest} = get_nutrient_category(rest, "SFA", "Fatty acids, total saturated")
    {tfa_all, rest} = get_nutrient_category(rest, "TFA", "Fatty acids, total trans")
    {vitamins, rest} = Enum.split_with(rest, fn x -> String.contains?(x.name, "Vitamin") end)

    vitamins_all =
      case length(vitamins) > 0 do
        true ->
          %{name: "Vitamins", amount: nil, measurement_unit: nil, children: vitamins}

        false ->
          nil
      end

    nuts_pre = [mufa_all, pufa_all, sfa_all, tfa_all, vitamins_all]
    nuts_pre = Enum.filter(nuts_pre, fn x -> !is_nil(x) end)

    nuts_pre =
      Enum.map(nuts_pre, fn x ->
        case is_map(x) do
          true ->
            x

          false ->
            Enum.into(x, %{})
        end
      end)

    nutrients = nuts_pre ++ rest
    nutrients = Enum.filter(nutrients, fn x -> !is_nil(x) end)
    energy = Enum.find(nutrients, fn x -> String.contains?(x.name, "Energy") end)

    energy =
      case energy.measurement_unit do
        "kilojoule" ->
          %{energy | amount: energy.amount * 0.2390057361, measurement_unit: "kcal"}

        _ ->
          energy
      end

    carb = Enum.find(nutrients, fn x -> String.contains?(x.name, "Carbohydrate") end)
    protein = Enum.find(nutrients, fn x -> String.contains?(x.name, "Protein") end)
    fiber = Enum.find(nutrients, fn x -> String.contains?(x.name, "Fiber") end)
    fat = Enum.find(nutrients, fn x -> String.contains?(x.name, "Total lipid") end)

    primaries = [energy, fat, carb, protein, fiber]
    primaries = Enum.filter(primaries, fn x -> !is_nil(x) end)
    nutrients = Enum.filter(nutrients, fn x -> x not in primaries end)
    nutrients = primaries ++ nutrients

    #user = socket.assigns.user
    query_str = ""

    #user_profile =
     # case is_nil(user) do
      #  true ->
       #   nil

       # false ->
        #  Accounts.get_user_profile_by_user_id(user.id)
     # end

    #changeset =
     # %RecipeSearchItem{query_string: nil}
      #|> Search.change_recipe_search_item(%{query_string: query_str})

    {_query, {recipes, cursor_after}} =
      case query_str do
        nil ->
          {query_str, list_recipes()}

        qr ->
          Food.search_recipe(qr)
      end

    #user_recipes =
     # case is_nil(user) do
      #  true ->
      #   []

       # false ->
        #  Users.list_user_saved_recipes(user)
         # |> Enum.map(fn x -> x.recipe_id end)
     # end

    socket
    |> assign(:nutrients, nutrients)
    |> assign(:primary_size, length(primaries))
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

  defp get_nutrient_category(nutrients, category_name, category_sum_name) do
    {category, rest} =
      Enum.split_with(nutrients, fn x -> String.contains?(x.name, category_name) end)

    case length(category) > 0 do
      true ->
        {category_total, rest} =
          Enum.split_with(rest, fn x ->
            String.contains?(x.name, category_sum_name)
          end)

        case length(category_total) == 1 do
          true ->
            {Enum.into(Enum.at(category_total, 0), children: category), rest}

          false ->
            {%{
               amount: 111.1,
               measurement_unit: "to be defined",
               children: category,
               name: category_sum_name
             }, rest}
        end

      false ->
        {nil, rest}
    end
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
