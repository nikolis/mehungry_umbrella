defmodule MehungryWeb.ProfileLive.Index do
  use MehungryWeb, :live_view
  use MehungryWeb.Searchable, :transfers_to_search
  use MehungryWeb.LiveHelpers, :hook_for_update_recipe_details_component
  use MehungryWeb.Presence, :user_tracking

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
     |> assign(:user_recipes, [])
     |> assign(:current_user, user)
     |> assign(:user, nil)}
  end

  @impl true
  def handle_params(params, uri, socket) do
    socket = assign(socket, :path, uri)
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    categories = Food.list_categories()
    category_ids = Enum.map(categories, fn x -> x.id end)
    food_restrictions = Food.list_food_restriction_types()
    food_restriction_ids = Enum.map(food_restrictions, fn x -> x.id end)

    user_profile = Accounts.get_user_profile_by_user_id(socket.assigns.current_user.id)

    #    user_profile = socket.assigns.user_profile
    changeset = Accounts.change_user_profile(user_profile, %{})
    maybe_track_user(%{}, socket)

    socket =
      socket
      |> assign(:page_title, "Edit Profile Details")
      |> assign(:categories, categories)
      |> assign(:current_user_profile, user_profile)
      |> assign(:user_profile, user_profile)
      |> assign(:category_ids, category_ids)
      |> assign(:food_restriction_ids, food_restriction_ids)
      |> assign(:food_restrictions, food_restrictions)
      |> assign(:form, to_form(changeset))
      |> assign(:id, "form-#{System.unique_integer()}")

    {current_user_profile, user_follows, current_user_recipes} =
      Accounts.get_user_essentials(socket.assigns.current_user)

    {user_saved_recipes, user_created_recipes} =
      case is_nil(socket.assigns.current_user) do
        true ->
          {[], []}

        false ->
          {Users.list_user_saved_recipes(socket.assigns.current_user),
           Users.list_user_created_recipes(socket.assigns.current_user)}
      end

    socket
    |> assign(:page_title, "Profile")
    |> assign(:user_created_recipes, user_created_recipes)
    |> assign(:user_saved_recipes, user_saved_recipes)
    |> assign(:current_user_recipes, current_user_recipes)
    |> assign(:current_user_profile, current_user_profile)
    |> assign(:user_profile, current_user_profile)
    |> assign(:current_user_follows, user_follows)
  end

  defp apply_action(socket, :show, %{"id" => id} = _params) do
    maybe_track_user(%{}, socket)

    user = Accounts.get_user!(id)

    {current_user_profile, current_user_follows, current_user_recipes} =
      Accounts.get_user_essentials(socket.assigns.current_user)

    categories = Food.list_categories()
    category_ids = Enum.map(categories, fn x -> x.id end)
    food_restrictions = Food.list_food_restriction_types()
    food_restriction_ids = Enum.map(food_restrictions, fn x -> x.id end)

    user_profile = Accounts.get_user_profile_by_user_id(socket.assigns.current_user.id)

    #    user_profile = socket.assigns.user_profile
    changeset = Accounts.change_user_profile(user_profile, %{})

    socket =
      socket
      |> assign(:categories, categories)
      |> assign(:current_user_profile, user_profile)
      |> assign(:user_profile, user_profile)
      |> assign(:category_ids, category_ids)
      |> assign(:food_restriction_ids, food_restriction_ids)
      |> assign(:food_restrictions, food_restrictions)
      |> assign(:form, to_form(changeset))
      |> assign(:id, "form-#{System.unique_integer()}")

    {user_saved_recipes, user_created_recipes, user_profile} =
      case is_nil(user) do
        true ->
          {[], [], []}

        false ->
          {Users.list_user_saved_recipes(user), Users.list_user_created_recipes(user),
           Accounts.get_user_profile_by_user_id(user.id)}
      end

    user_recipes = Enum.map(user_saved_recipes, fn x -> x.recipe_id end)

    socket
    |> assign(:page_title, "Profile")
    |> assign(:user, user)
    |> assign(:page_title, "Profile " <> user.email)
    |> assign(:user_created_recipes, user_created_recipes)
    |> assign(:user_saved_recipes, user_saved_recipes)
    |> assign(:current_user_recipes, current_user_recipes)
    |> assign(:current_user_profile, current_user_profile)
    |> assign(:user_profile, user_profile)
    |> assign(:user_recipes, user_recipes)
    |> assign(:user_follows, [])
    |> assign(:current_user_follows, current_user_follows)
  end

  defp apply_action(socket, :show_recipe, %{"recipe_id" => id}) do
    maybe_track_user(%{}, socket)

    recipe = Food.get_recipe!(id)
    Posts.subscribe_to_recipe(%{recipe_id: id})

    cancel_path =
      if not is_nil(socket.assigns.user) and not is_nil(socket.assigns.current_user) do
        ~p"/profile/#{socket.assigns.user.id}"
      else
        ~p"/profile"
      end

    {primaries_length, nutrients} = RecipeUtils.get_nutrients(recipe)

    {current_user_profile, current_user_follows, current_user_recipes} =
      Accounts.get_user_essentials(socket.assigns.current_user)

    socket
    |> assign(:nutrients, nutrients)
    |> assign(:primary_size, primaries_length)
    |> assign(:page_title, recipe.title <> " from " <> recipe.user.email)
    |> assign(:recipe, recipe)
    |> assign(:current_user_follows, current_user_follows)
    # |> assign(:user_recipes, user_recipes)
    |> assign(:current_user_recipes, current_user_recipes)
    |> assign(:current_user_profile, current_user_profile)
    |> assign(:cancel_path, cancel_path)
  end

  defp apply_action(socket, :edit, _params) do
    maybe_track_user(%{}, socket)
    categories = Food.list_categories()
    category_ids = Enum.map(categories, fn x -> x.id end)
    food_restrictions = Food.list_food_restriction_types()
    food_restriction_ids = Enum.map(food_restrictions, fn x -> x.id end)
    user_profile = Accounts.get_user_profile_by_user_id(socket.assigns.current_user.id)

    #    user_profile = socket.assigns.user_profile
    changeset = Accounts.change_user_profile(user_profile, %{})

    socket
    |> assign(:page_title, "Edit Profile Details")
    |> assign(:categories, categories)
    |> assign(:current_user_profile, user_profile)
    |> assign(:user_profile, user_profile)
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
    user_saved_recipes = Users.list_user_saved_recipes(socket.assigns.current_user)

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

      "edit_profile" ->
        {:noreply,
         socket
         |> assign(content_state: :edit_profile)}
    end
  end

  def get_profile_content(%{content_state: :created} = assigns) do
    ~H"""
    <div class="grid_even_columns p-4">
      <%= for recipe <- @user_created_recipes do %>
        <RecipeComponents.recipe_card
          recipe={recipe}
          type={if @live_action == :show, do: "browse", else: "created"}
          return_to="profile"
          user_recipes={@user_recipes}
          path_to_details={"/profile/show_recipe/#{recipe.id}"}
          id={"recipe" <> Integer.to_string(recipe.id)}
        />
      <% end %>
    </div>
    """
  end

  def get_profile_content(%{content_state: :saved} = assigns) do
    ~H"""
    <div class="grid_even_columns p-4">
      <%= for user_recipe <- @user_saved_recipes do %>
        <RecipeComponents.recipe_card
          recipe={user_recipe.recipe}
          type={if @live_action == :show, do: "browse", else: "saved"}
          return_to="profile"
          user_recipes={@user_recipes}
          path_to_details={"/profile/show_recipe/#{user_recipe.recipe.id}"}
          id={"recipe" <> Integer.to_string(user_recipe.recipe.id)}
        />
      <% end %>
    </div>
    """
  end

  def get_profile_content(%{content_state: :edit_profile} = assigns) do
    ~H"""
    <.live_component
      module={MehungryWeb.ProfileLive.Form}
      categories={@categories}
      category_ids={@category_ids}
      food_restriction_ids={@food_restriction_ids}
      food_restrictions={@food_restrictions}
      id="hero"
      user_profile={@current_user_profile}
      live_action={@live_action}
      current_user={@current_user}
      title={@page_title}
      action={@live_action}
      form={@form}
    />
    """
  end
end
