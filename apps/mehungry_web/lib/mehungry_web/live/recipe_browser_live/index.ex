defmodule MehungryWeb.RecipeBrowseLive.Index do
  use MehungryWeb, :live_view
  alias Phoenix.LiveView.JS

  alias Vix.Vips.Flag
  alias Mehungry.Food
  alias Mehungry.Food.Recipe
  alias Mehungry.Search.RecipeSearchItem
  alias Mehungry.Search
  alias MehungryWeb.Presence
  alias MehungryWeb.ImageProcessing
  alias Mehungry.Accounts
  alias Mehungry.Users
  alias MehungryWeb.RecipeBrowseLive.Components
  alias Mehungry.Food.RecipeUtils

  @impl true
  def mount(_params, session, socket) do
    user = Accounts.get_user_by_session_token(session["user_token"])

    {recipes, cursor_after} = list_recipes()
    user_recipes = Users.list_user_saved_recipes(user)
    user_recipes = Enum.map(user_recipes, fn x -> x.recipe_id end)

    {:ok,
     assign(socket, :recipes, recipes)
     |> assign(:cursor_after, cursor_after)
     |> assign(:recipe, nil)
     |> assign(:user_recipes, user_recipes)
     |> assign(:page, 1)
     |> assign(:invocations, 0)
     |> assign(:counter, 1)
     |> assign(:user, user)
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
  def handle_event("close-modal", _thing, socket) do
    {:noreply, push_patch(socket, to: "/browse")}
  end

  @impl true
  def handle_event("save_user_recipe", %{"recipe_id" => recipe_id}, socket) do
    {recipe_id, _ignore} = Integer.parse(recipe_id)
    toggle_user_saved_recipes(socket, recipe_id)
    user_recipes = Users.list_user_saved_recipes(socket.assigns.user)
    user_recipes = Enum.map(user_recipes, fn x -> x.recipe_id end)
    socket = assign(socket, :user_recipes, user_recipes)
    {:noreply, push_patch(socket, to: "/browse")}
  end

  def toggle_user_saved_recipes(socket, recipe_id) do
    case Enum.any?(socket.assigns.user_recipes, fn x -> x == recipe_id end) do
      true ->
        Users.remove_user_saved_recipe(socket.assigns.user.id, recipe_id)

      false ->
        Users.save_user_recipe(socket.assigns.user.id, recipe_id)
    end
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
    socket = assign(socket, :invocations, 0)
    {:noreply, push_patch(socket, to: "/browse/" <> recipe_id)}
  end

  def handle_event("search", %{"recipe_search_item" => %{"query_string" => query_string}}, socket) do
    {result, cursor_after} = Food.search_recipe(query_string)

    result =
      Enum.map(result, fn recipe ->
        return = ImageProcessing.resize(recipe.image_url, 100, 100)
        %Recipe{recipe | recipe_image_remote: return}
      end)

    {result, cursor_after}

    {:noreply,
     socket
     |> assign(:cursor_after, cursor_after)
     |> assign(:page, 1)
     |> assign(:recipes, result)}
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
    |> assign(:nutrients, nil)
    |> assign(:recipe_nutrients, nil)
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

  defp apply_action(socket, :show, %{"id" => id}) do
    recipe = Food.get_recipe!(id)

    recipe_nutrients = RecipeUtils.calculate_recipe_nutrition_value(recipe)

    rest =
      Enum.filter(recipe_nutrients.flat_recipe_nutrients, fn x ->
        Float.round(x.amount, 4) != 0
      end)

    {mufa_all, rest} = get_nutrient_category(rest, "MUFA", "Fatty acids, total monounsaturated")
    {pufa_all, rest} = get_nutrient_category(rest, "PUFA", "Fatty acids, total polyunsaturated")
    {sfa_all, rest} = get_nutrient_category(rest, "SFA", "Fatty acids, total saturated")
    {tfa_all, rest} = get_nutrient_category(rest, "TFA", "Fatty acids, total trans")

    {vitamins, rest} = Enum.split_with(rest, fn x -> String.contains?(x.name, "Vitamin") end)

    vitamins_all =
      case length(vitamins) > 0 do
        true ->
          Enum.into(%{name: "Vitamins", amount: nil, measurement_unit: nil}, children: vitamins)

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

    socket
    |> assign(:page_title, "Recipe Details")
    |> assign(:nutrients, nutrients)
    |> assign(:recipe, recipe)
    |> assign(:recipe_nutrients, recipe_nutrients)
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
