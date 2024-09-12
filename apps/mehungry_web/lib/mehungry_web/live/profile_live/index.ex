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
    user = Accounts.get_user_by_session_token(session["user_token"])

    user_profile =
      case Accounts.get_user_profile_by_user_id(user.id) do
        nil ->
          {:ok, _profile} =
            Accounts.create_user_profile(%{user_id: user.id, user_category_rules: []})

          Accounts.get_user_profile_by_user_id(user.id)

        profile ->
          profile
      end

    user_saved_recipes = Users.list_user_saved_recipes(user)
    user_created_recipes = Users.list_user_created_recipes(user)

    {:ok,
     assign(socket, :content_state, :created)
     |> assign(:user_profile, user_profile)
     |> assign(
       :invocations,
       case Map.get(socket.assigns, :invocations) do
         nil ->
           1

         x ->
           x + 1
       end
     )
     |> assign(:recipe, nil)
     |> assign(:user_saved_recipes, user_saved_recipes)
     |> assign(:user, user)
     |> assign(:counter, 1)
     |> assign(:user_created_recipes, user_created_recipes)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    profile = Accounts.get_user_profile_by_user_id(socket.assigns.user.id)

    socket
    |> assign(:page_title, "Profile")
    |> assign(:user_profile, profile)
  end

  defp apply_action(socket, :show, %{"id" => id} = _params) do
    profile = Accounts.get_user_profile_by_user_id(id)

    socket
    |> assign(:page_title, "Profile")
    |> assign(:user_profile, profile)
  end

  defp apply_action(socket, :show_recipe, %{"recipe_id" => id}) do
    recipe = Food.get_recipe!(id)
    Posts.subscribe_to_recipe(%{recipe_id: id})

    {primaries_length, nutrients} = RecipeUtils.get_nutrients(recipe)
    user = socket.assigns.user

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
    |> assign(:recipe, recipe)
    |> assign(:user_recipes, user_recipes)
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
    Users.remove_user_saved_recipe(socket.assigns.user.id, String.to_integer(id))
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
