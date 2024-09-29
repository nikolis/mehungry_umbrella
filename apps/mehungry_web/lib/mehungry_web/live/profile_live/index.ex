defmodule MehungryWeb.ProfileLive.Index do
  use MehungryWeb, :live_view
  use MehungryWeb.Searchable, :transfers_to_search
  use MehungryWeb.LiveHelpers, :hook_for_update_recipe_details_component

  alias MehungryWeb.RecipeComponents

  alias Mehungry.Accounts
  alias Mehungry.Users
  alias MehungryWeb.ProfileLive.Show
  alias Mehungry.Food
  alias Mehungry.Posts
  alias Mehungry.Food.RecipeUtils

  def mount_search(_params, session, socket) do
    user =
      case is_nil(session["user_token"]) do
        true ->
          nil

        false ->
          Accounts.get_user_by_session_token(session["user_token"])
      end

    {:ok,
     assign(socket, :content_state, :created)
     |> assign(:recipe, nil)
     |> assign(:current_user, user)
     |> assign(:user, nil)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    user_profile =
      case is_nil(socket.assigns.current_user) do
        true ->
          nil

        false ->
          Accounts.get_user_profile_by_user_id(socket.assigns.current_user.id)
      end

    current_user_recipes =
      case is_nil(socket.assigns.current_user) do
        true ->
          []

        false ->
          Users.list_user_saved_recipes(socket.assigns.current_user)
          |> Enum.map(fn x -> x.recipe_id end)
      end

    {user_saved_recipes, user_created_recipes, user_follows} =
      case is_nil(socket.assigns.current_user) do
        true ->
          {[], []}

        false ->
          user_follows = Users.list_user_follows(socket.assigns.current_user)
          user_follows = Enum.map(user_follows, fn x -> x.follow_id end)

          {Users.list_user_saved_recipes(socket.assigns.current_user),
           Users.list_user_created_recipes(socket.assigns.current_user), user_follows}
      end

    socket
    |> assign(:page_title, "Profile")
    |> assign(:user_created_recipes, user_created_recipes)
    |> assign(:user_saved_recipes, user_saved_recipes)
    |> assign(:current_user_recipes, current_user_recipes)
    |> assign(:user_profile, user_profile)
    |> assign(:user_follows, user_follows)
  end

  defp apply_action(socket, :show, %{"id" => id} = _params) do
    user = Accounts.get_user!(id)

    user_profile =
      case is_nil(user) do
        true ->
          nil

        false ->
          Accounts.get_user_profile_by_user_id(user.id)
      end

    current_user_recipes =
      case is_nil(socket.assigns.current_user) do
        true ->
          []

        false ->
          Users.list_user_saved_recipes(socket.assigns.current_user)
          |> Enum.map(fn x -> x.recipe_id end)
      end

    {user_saved_recipes, user_created_recipes, user_follows} =
      case is_nil(socket.assigns.current_user) do
        true ->
          {Users.list_user_saved_recipes(user), Users.list_user_created_recipes(user), []}

        false ->
          user_follows = Users.list_user_follows(socket.assigns.current_user)
          user_follows = Enum.map(user_follows, fn x -> x.follow_id end)

          {Users.list_user_saved_recipes(user), Users.list_user_created_recipes(user),
           user_follows}
      end

    socket
    |> assign(:page_title, "Profile")
    |> assign(:user, user)
    |> assign(:page_title, "Profile " <> user.email )
    |> assign(:user_created_recipes, user_created_recipes)
    |> assign(:user_saved_recipes, user_saved_recipes)
    |> assign(:current_user_recipes, current_user_recipes)
    |> assign(:user_profile, user_profile)
    |> assign(:user_follows, user_follows)
  end

  defp apply_action(socket, :show_recipe, %{"recipe_id" => id}) do
    recipe = Food.get_recipe!(id)
    Posts.subscribe_to_recipe(%{recipe_id: id})

    cancel_path =
      if not is_nil(socket.assigns.user) and not is_nil(socket.assigns.current_user) do
        ~p"/profile/#{socket.assigns.user.id}"
      else
        ~p"/profile"
      end

    {primaries_length, nutrients} = RecipeUtils.get_nutrients(recipe)
    user = socket.assigns.user

    user_follows =
      if is_nil(socket.assigns.user) do
        nil
      else
        case recipe.user_id == socket.assigns.user.id do
          true ->
            nil

          false ->
            Users.list_user_follows(user)
            |> Enum.map(fn x -> x.follow_id end)
        end
      end

    current_user_recipes =
      case is_nil(socket.assigns.current_user) do
        true ->
          []

        false ->
          Users.list_user_saved_recipes(socket.assigns.current_user)
          |> Enum.map(fn x -> x.recipe_id end)
      end

    user_recipes =
      case is_nil(user) do
        true ->
          []

        false ->
          Users.list_user_saved_recipes(user)
          |> Enum.map(fn x -> x.recipe_id end)
      end


    socket
    |> assign(:nutrients, nutrients)
    |> assign(:primary_size, primaries_length)
    |> assign(:page_title, recipe.title <> " from "  <> recipe.user.email )
    |> assign(:recipe, recipe)
    |> assign(:user_follows, user_follows)
    |> assign(:user_recipes, user_recipes)
    |> assign(:current_user_recipes, current_user_recipes)
    |> assign(:cancel_path, cancel_path)
  end

  defp apply_action(socket, :edit, _params) do
    categories = Food.list_categories()
    category_ids = Enum.map(categories, fn x -> x.id end)
    food_restrictions = Food.list_food_restriction_types()
    food_restriction_ids = Enum.map(food_restrictions, fn x -> x.id end)

    user_profile = socket.assigns.user_profile
    changeset = Accounts.change_user_profile(user_profile, %{})

    socket
    |> assign(:page_title, "Edit Profile Details")
    |> assign(:categories, categories)
    |> assign(:category_ids, category_ids)
    |> assign(:food_restriction_ids, food_restriction_ids)
    |> assign(:food_restrictions, food_restrictions)
    |> assign(:form, to_form(changeset))
    |> assign(:id, "form-#{System.unique_integer()}")
  end

  @impl true
  def handle_info({MehungryWeb.Onboarding.FormComponent, "profile-saved"}, socket) do
    user_profile = Accounts.get_user_profile_by_user_id(socket.assigns.user.id)

    {:noreply,
     socket
     |> assign(:user_profile, user_profile)}
  end

  def get_active(state, param) do
    if state == param do
      "active"
    else
      ""
    end
  end

  def handle_event("edit-recipe", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> push_navigate(to: "/create_recipe/#{id}")}
  end

  def handle_event("unsave-recipe", %{"id" => id}, socket) do
    Users.remove_user_saved_recipe(socket.assigns.current_user.id, String.to_integer(id))
    IO.inspect(socket.assigns.user)
    user_saved_recipes = Users.list_user_saved_recipes(socket.assigns.user)

    {:noreply,
     socket
     |> assign(:user_saved_recipes, user_saved_recipes)}
  end

  def handle_event("delete", %{"id" => _id}, socket) do
    # measurement_unit = food.get_measurement_unit!(id)
    # {:ok, _} = food.delete_measurement_unit(measurement_unit)

    # assign(socket, :measurement_units, list_measurement_units())}
    {:noreply, socket}
  end

  def handle_event("delete_recipe", %{"id" => id}, socket) do
    Food.delete_recipe(id)
    user_saved_recipes = Users.list_user_saved_recipes(socket.assigns.user)
    user_created_recipes = Users.list_user_created_recipes(socket.assigns.user)

    socket =
      socket
      |> assign(:user_saved_recipes, user_saved_recipes)
      |> assign(:user_created_recipes, user_created_recipes)

    {:noreply, socket}
  end

  @impl true
  def handle_event("content_state_change", %{"state" => state}, socket) do
    case state do
      "created" ->
        {:noreply,
         socket
         |> assign(content_state: :created)}

      "saved" ->
        {:noreply,
         socket
         |> assign(content_state: :saved)}
    end
  end
end
