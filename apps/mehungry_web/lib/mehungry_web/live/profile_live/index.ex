defmodule MehungryWeb.ProfileLive.Index do
  use MehungryWeb, :live_view
  use MehungryWeb.Presence, :user_tracking

  use MehungryWeb.LiveHelpers, :hook_for_update_recipe_details_component

  alias MehungryWeb.RecipeComponents
  alias MehungryWeb.RecipeFlags

  alias Mehungry.Accounts
  alias Mehungry.Users
  alias MehungryWeb.ProfileLive.Show
  alias Mehungry.Food
  alias Mehungry.Posts

  @impl true
  def mount(_params, session, socket) do
    current_user =
      case is_nil(session["user_token"]) do
        true ->
          nil

        false ->
          Accounts.get_user_by_session_token(session["user_token"])
      end

    {current_user_profile, current_user_follows, current_user_recipes} =
      Accounts.get_user_essentials(current_user)

    current_user_follows = Enum.map(current_user_follows, fn x -> x.follow_id end)

    {:ok,
     assign(socket, :content_state, :created)
     |> assign(:recipe, nil)
     |> assign(:user_recipes, [])
     |> assign(:user_ingredients, [])
     |> assign(:friends_ingredients, [])
     |> assign(:current_user, current_user)
     |> assign(:user, nil)
     |> assign(:must_be_loged_in, nil)
     |> assign(:current_user_profile, current_user_profile)
     |> assign(:current_user_follows, current_user_follows)
     |> assign(:current_user_recipes, current_user_recipes)}
  end

  @impl true
  def handle_params(params, uri, socket) do
    socket = assign(socket, :path, uri)
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  @profile_tabs ~w(created saved my_ingredients friends_ingredients edit_profile connected_accounts)

  defp content_state_from_tab(tab, live_action) when tab in @profile_tabs do
    case {tab, live_action} do
      {tab, :show}
      when tab in ["edit_profile", "connected_accounts", "my_ingredients", "friends_ingredients"] ->
        :created

      {tab, _live_action} ->
        String.to_existing_atom(tab)
    end
  end

  defp content_state_from_tab(_tab, _live_action), do: :created

  defp apply_action(socket, :index, params) do
    if is_nil(socket.assigns[:current_user]) do
      push_navigate(socket, to: "/users/log_in")
    else
      content_state = content_state_from_tab(params["tab"], :index)

      do_apply_action_index(socket, content_state)
      |> assign(:content_state, content_state)
    end
  end

  defp apply_action(socket, :show, %{"id" => id} = params) do
    maybe_track_user(%{}, socket)

    user = Accounts.get_user!(id)

    categories = Food.list_categories()
    category_ids = Enum.map(categories, fn x -> x.id end)
    food_restrictions = Food.list_food_restriction_types()
    food_restriction_ids = Enum.map(food_restrictions, fn x -> x.id end)

    changeset = Accounts.change_user_profile(socket.assigns.current_user_profile, %{})

    socket =
      socket
      |> assign(:categories, categories)
      |> assign(:category_ids, category_ids)
      |> assign(:food_restriction_ids, food_restriction_ids)
      |> assign(:food_restrictions, food_restrictions)
      |> assign(:id, "form-#{System.unique_integer()}")
      |> assign(:form, to_form(changeset))

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
    |> assign(:user_profile, user_profile)
    |> assign(:user_recipes, user_recipes)
    |> assign(:content_state, content_state_from_tab(params["tab"], :show))
  end

  defp apply_action(socket, :show_recipe, %{"recipe_id" => id}) do
    maybe_track_user(%{}, socket)

    recipe = Food.get_recipe!(id)

    if !is_nil(recipe) do
      Posts.subscribe_to_recipe(%{recipe_id: id})

      cancel_path =
        if not is_nil(socket.assigns.user) and not is_nil(socket.assigns.current_user) do
          ~p"/profile/#{socket.assigns.user.id}?#{[tab: to_string(socket.assigns.content_state)]}"
        else
          ~p"/profile?#{[tab: to_string(socket.assigns.content_state)]}"
        end

      {current_user_profile, current_user_follows, current_user_recipes} =
        Accounts.get_user_essentials(socket.assigns.current_user)

      socket
      |> assign(:nutrients, recipe.nutrients)
      |> assign(:primary_size, recipe.primary_nutrients_size)
      |> assign(:page_title, recipe.title <> " from " <> recipe.user.email)
      |> assign(:recipe, recipe)
      |> assign(:current_user_follows, current_user_follows)
      # |> assign(:user_recipes, user_recipes)
      |> assign(:current_user_recipes, current_user_recipes)
      |> assign(:current_user_profile, current_user_profile)
      |> assign(:cancel_path, cancel_path)
    else
      socket |> put_flash(:error, "Recipe not found") |> push_navigate(to: "/home")
    end
  end

  defp apply_action(socket, :edit, _params) do
    if is_nil(socket.assigns[:current_user]) do
      push_navigate(socket, to: "/users/log_in")
    else
      do_apply_action_edit(socket)
    end
  end

  defp do_apply_action_edit(socket) do
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

  defp do_apply_action_index(socket, content_state) do
    categories = Food.list_categories()
    category_ids = Enum.map(categories, fn x -> x.id end)
    food_restrictions = Food.list_food_restriction_types()
    food_restriction_ids = Enum.map(food_restrictions, fn x -> x.id end)

    changeset = Accounts.change_user_profile(socket.assigns.current_user_profile, %{})
    maybe_track_user(%{}, socket)

    socket =
      socket
      |> assign(:page_title, "Edit Profile Details")
      |> assign(:categories, categories)
      |> assign(:category_ids, category_ids)
      |> assign(:food_restriction_ids, food_restriction_ids)
      |> assign(:food_restrictions, food_restrictions)
      |> assign(:form, to_form(changeset))
      |> assign(:id, "form-#{System.unique_integer()}")

    condition_ids = RecipeFlags.opted_in_condition_ids(socket.assigns.current_user_profile)
    current_user = socket.assigns.current_user

    # Only the active tab's recipe list is rendered, so load just that one. The
    # other assign stays [] and is filled in when the user switches tabs.
    {user_saved_recipes, user_created_recipes} =
      case {content_state, is_nil(current_user)} do
        {_content_state, true} -> {[], []}
        {:created, false} -> {[], load_created_recipes(current_user, condition_ids)}
        {:saved, false} -> {load_saved_recipes(current_user, condition_ids), []}
        {_content_state, false} -> {[], []}
      end

    # Ingredient lists are only rendered by the two ingredient tabs — skip the
    # queries entirely on the default created/saved tabs. mount/3 seeds both to
    # [], so the non-active tab's assign stays empty here.
    {user_ingredients, friends_ingredients} =
      case content_state do
        :my_ingredients ->
          {Food.list_user_ingredients(socket.assigns.current_user), []}

        :friends_ingredients ->
          {[], Food.list_friends_ingredients(socket.assigns.current_user)}

        _ ->
          {[], []}
      end

    socket
    |> assign(:page_title, "Profile")
    |> assign(:user_created_recipes, user_created_recipes)
    |> assign(:user_saved_recipes, user_saved_recipes)
    |> assign(:user_ingredients, user_ingredients)
    |> assign(:friends_ingredients, friends_ingredients)
  end

  defp load_created_recipes(user, condition_ids) do
    user
    |> Users.list_user_created_recipes()
    |> RecipeFlags.enrich(condition_ids)
  end

  defp load_saved_recipes(user, condition_ids) do
    saved = Users.list_user_saved_recipes(user)

    # Batch-enrich the saved recipes in one query instead of calling enrich_one
    # per UserRecipe (which fired a flags_for_recipe query each).
    enriched_by_id =
      saved
      |> Enum.map(& &1.recipe)
      |> RecipeFlags.enrich(condition_ids)
      |> Map.new(fn recipe -> {recipe.id, recipe} end)

    Enum.map(saved, fn ur ->
      %{ur | recipe: Map.get(enriched_by_id, ur.recipe.id, ur.recipe)}
    end)
  end

  @impl true
  def handle_info({MehungryWeb.Onboarding.FormComponent, "profile-saved"}, socket) do
    current_user_profile =
      Accounts.get_user_profile_by_user_id(socket.assigns.current_user.id)

    {:noreply,
     socket
     |> assign(:current_user_profile, current_user_profile)}
  end

  def handle_info(
        {MehungryWeb.ProfileLive.Form, {:saved, %Mehungry.Accounts.UserProfile{} = profile}},
        socket
      ) do
    {:noreply,
     socket
     |> assign(:current_user_profile, profile)
     |> put_flash(:info, "Upadated successfully")}
  end

  def get_active(state, param) do
    if state == param do
      " bg-ink-panel text-paprika border-b-2 border-paprika "
    else
      " text-parchment-dim hover:text-parchment hover:bg-ink-panel/50"
    end
  end

  def tab_path(%{live_action: :show, user: user}, tab), do: ~p"/profile/#{user.id}?#{[tab: tab]}"
  def tab_path(%{live_action: :index}, tab), do: ~p"/profile?#{[tab: tab]}"

  def handle_event("add_friend", %{"id" => id}, socket) do
    requester_id = socket.assigns.current_user.id

    {message, new_status} =
      case Mehungry.Friends.send_friend_request(requester_id, String.to_integer(id)) do
        {:ok, _} ->
          {{:info, "Friend request sent."}, :request_sent}

        {:error, :already_friends} ->
          {{:info, "You are already friends."}, :friends}

        {:error, :already_requested} ->
          {{:info, "You already have a pending request to this user."}, :request_sent}

        {:error, :self} ->
          {{:error, "You can't friend yourself."}, nil}

        {:error, _} ->
          {{:error, "Could not send friend request."}, nil}
      end

    # Refresh the profile card's button in place so the outcome is visible
    # immediately, without a page reload.
    if new_status, do: send_update(Show, id: "hero", friend_status: new_status)

    {:noreply, put_flash(socket, elem(message, 0), elem(message, 1))}
  end

  def handle_event("delete_my_ingredient", %{"id" => id}, socket) do
    # Re-fetch through the owner-scoped getter so a forged id can't delete
    # someone else's ingredient.
    ingredient = Food.get_user_ingredient!(socket.assigns.current_user, id)
    {:ok, _} = Food.delete_ingredient(ingredient)

    {:noreply,
     socket
     |> assign(:user_ingredients, Food.list_user_ingredients(socket.assigns.current_user))
     |> put_flash(:info, "Ingredient deleted")}
  end

  def handle_event("edit-recipe", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> push_navigate(to: "/create_recipe/#{id}")}
  end

  def handle_event("keep_browsing", _thing, socket) do
    {:noreply, assign(socket, :must_be_loged_in, nil)}
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

  def handle_event("disconnect_social", %{"provider" => provider}, socket) do
    user = socket.assigns.current_user
    token_key = "#{provider}_token"
    Accounts.update_user_tokens(user, %{token_key => %{}})
    updated_user = Accounts.get_user!(user.id)

    {:noreply,
     socket
     |> assign(:current_user, updated_user)
     |> put_flash(:info, "#{String.capitalize(provider)} account disconnected.")}
  end

  def get_profile_content(%{content_state: :created} = assigns) do
    ~H"""
    <div class="pb-20 w-full grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-6  px-4">
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
    <div class="pb-20 w-full grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-6 px-4">
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

  def get_profile_content(%{content_state: :my_ingredients} = assigns) do
    ~H"""
    <div class="pb-20 w-full max-w-3xl mx-auto px-4">
      <div class="flex items-center justify-between mb-4">
        <h3 class="text-lg font-display font-medium text-parchment">My Ingredients</h3>
        <.link
          navigate={~p"/my_ingredients/new"}
          class="px-4 py-2 rounded-full bg-paprika hover:bg-paprika-soft text-ink font-bold text-sm transition-colors"
        >
          + Create ingredient
        </.link>
      </div>

      <%= if @user_ingredients == [] do %>
        <div class="text-parchment-dim text-sm border border-ink-panel2 bg-ink-panel rounded-xl p-6 text-center">
          You haven't created any ingredients yet. Create one to use it in your
          recipes, meal plans, and shopping basket.
        </div>
      <% else %>
        <div class="space-y-3">
          <div
            :for={ingredient <- @user_ingredients}
            class="flex items-center justify-between border border-ink-panel2 bg-ink-panel rounded-xl p-4"
          >
            <div class="min-w-0">
              <div class="text-parchment font-medium truncate">{ingredient.name}</div>
              <div class="text-parchment-dim text-xs">
                {length(ingredient.ingredient_nutrients)} nutrients
              </div>
            </div>
            <div class="flex items-center gap-3 shrink-0">
              <.link
                navigate={~p"/my_ingredients/#{ingredient.id}/edit"}
                class="text-parchment-dim hover:text-parchment text-sm"
              >
                Edit
              </.link>
              <button
                type="button"
                phx-click="delete_my_ingredient"
                phx-value-id={ingredient.id}
                data-confirm="Delete this ingredient? This cannot be undone."
                class="text-parchment-dim hover:text-red-400 text-sm transition-colors"
              >
                Delete
              </button>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  def get_profile_content(%{content_state: :friends_ingredients} = assigns) do
    ~H"""
    <div class="pb-20 w-full max-w-3xl mx-auto px-4">
      <h3 class="text-lg font-display font-medium text-parchment mb-4">Friends' Ingredients</h3>

      <%= if @friends_ingredients == [] do %>
        <div class="text-parchment-dim text-sm border border-ink-panel2 bg-ink-panel rounded-xl p-6 text-center">
          None yet. Ingredients your friends create are shared with you here and
          become available in your recipes, meal plans, and shopping basket.
        </div>
      <% else %>
        <div class="space-y-3">
          <div
            :for={ingredient <- @friends_ingredients}
            class="flex items-center justify-between border border-ink-panel2 bg-ink-panel rounded-xl p-4"
          >
            <div class="min-w-0">
              <div class="text-parchment font-medium truncate">{ingredient.name}</div>
              <div class="text-parchment-dim text-xs">
                {length(ingredient.ingredient_nutrients)} nutrients · shared by {ingredient.user &&
                  (ingredient.user.name || ingredient.user.email)}
              </div>
            </div>
          </div>
        </div>
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

  def get_profile_content(%{content_state: :connected_accounts} = assigns) do
    facebook_connected =
      not is_nil(assigns.current_user) and
        map_size(Map.get(assigns.current_user, :facebook_token, %{})) > 0

    facebook_is_primary_login =
      facebook_connected and is_nil(assigns.current_user.hashed_password)

    pinterest_connected =
      not is_nil(assigns.current_user) and
        map_size(Map.get(assigns.current_user, :pinterest_token, %{})) > 0

    instagram_connected =
      not is_nil(assigns.current_user) and
        map_size(Map.get(assigns.current_user, :instagram_token, %{})) > 0

    assigns =
      assigns
      |> assign(:facebook_connected, facebook_connected)
      |> assign(:facebook_is_primary_login, facebook_is_primary_login)
      |> assign(:pinterest_connected, pinterest_connected)
      |> assign(:instagram_connected, instagram_connected)

    ~H"""
    <div class="max-w-2xl mx-auto px-4 py-6 flex flex-col gap-4 mb-10">
      <div class="bg-ink-panel border border-ink-panel2 rounded-xl p-5 flex items-center justify-between gap-4">
        <div class="flex items-center gap-4">
          <div class="w-12 h-12 rounded-full bg-blue-600 flex items-center justify-center flex-shrink-0">
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="white" class="w-6 h-6">
              <path d="M22 12c0-5.523-4.477-10-10-10S2 6.477 2 12c0 4.991 3.657 9.128 8.438 9.878V14.89h-2.54V12h2.54V9.797c0-2.506 1.492-3.89 3.777-3.89 1.094 0 2.238.195 2.238.195v2.46h-1.26c-1.243 0-1.63.771-1.63 1.562V12h2.773l-.443 2.89h-2.33v6.988C18.343 21.128 22 16.991 22 12z" />
            </svg>
          </div>
          <div>
            <p class="text-parchment font-semibold">Facebook</p>
            <p class="text-parchment-dim text-sm">
              {if @facebook_connected,
                do: "Connected — you can publish recipes to your Facebook pages",
                else: "Connect your account to publish recipes to your Facebook pages"}
            </p>
          </div>
        </div>
        <%= if @facebook_connected do %>
          <div class="flex flex-col items-end gap-1.5 flex-shrink-0">
            <span class="flex items-center gap-1.5 text-green-400 text-sm font-medium">
              <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
                <path
                  fill-rule="evenodd"
                  d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z"
                  clip-rule="evenodd"
                />
              </svg>
              {if @facebook_is_primary_login, do: "Primary login", else: "Connected"}
            </span>
            <%= if not @facebook_is_primary_login do %>
              <button
                phx-click="disconnect_social"
                phx-value-provider="facebook"
                data-confirm="Disconnect your Facebook account?"
                class="px-3 py-1.5 rounded-lg bg-ink-panel2 hover:bg-ink-panel text-parchment-dim text-xs font-medium transition"
              >
                Disconnect
              </button>
            <% end %>
          </div>
        <% else %>
          <a
            href="/auth/facebook"
            class="flex-shrink-0 px-4 py-2 rounded-lg bg-blue-600 hover:bg-blue-500 text-white text-sm font-medium transition"
          >
            Connect
          </a>
        <% end %>
      </div>

      <div class="bg-ink-panel border border-ink-panel2 rounded-xl p-5 flex items-center justify-between gap-4">
        <div class="flex items-center gap-4">
          <div class="w-12 h-12 rounded-xl bg-red-600 flex items-center justify-center flex-shrink-0">
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="white" class="w-6 h-6">
              <path d="M12 0C5.373 0 0 5.373 0 12c0 5.084 3.163 9.426 7.627 11.174-.105-.949-.2-2.405.042-3.441.218-.937 1.407-5.965 1.407-5.965s-.359-.719-.359-1.782c0-1.668.967-2.914 2.171-2.914 1.023 0 1.518.769 1.518 1.69 0 1.029-.655 2.568-.994 3.995-.283 1.194.599 2.169 1.777 2.169 2.133 0 3.772-2.249 3.772-5.495 0-2.873-2.064-4.882-5.012-4.882-3.414 0-5.418 2.561-5.418 5.207 0 1.031.397 2.138.893 2.738a.36.36 0 0 1 .083.345l-.333 1.36c-.053.22-.174.267-.402.161-1.499-.698-2.436-2.889-2.436-4.649 0-3.785 2.75-7.262 7.929-7.262 4.163 0 7.398 2.967 7.398 6.931 0 4.136-2.607 7.464-6.227 7.464-1.216 0-2.359-.632-2.75-1.378l-.748 2.853c-.271 1.043-1.002 2.35-1.492 3.146C9.57 23.812 10.763 24 12 24c6.627 0 12-5.373 12-12S18.627 0 12 0z" />
            </svg>
          </div>
          <div>
            <p class="text-parchment font-semibold">Pinterest</p>
            <p class="text-parchment-dim text-sm">
              {if @pinterest_connected,
                do: "Connected — you can pin recipes directly to your boards",
                else: "Connect your account to pin recipes to your Pinterest boards"}
            </p>
          </div>
        </div>
        <%= if @pinterest_connected do %>
          <div class="flex flex-col items-end gap-1.5 flex-shrink-0">
            <span class="flex items-center gap-1.5 text-green-400 text-sm font-medium">
              <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
                <path
                  fill-rule="evenodd"
                  d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z"
                  clip-rule="evenodd"
                />
              </svg>
              Connected
            </span>
            <button
              phx-click="disconnect_social"
              phx-value-provider="pinterest"
              data-confirm="Disconnect your Pinterest account?"
              class="px-3 py-1.5 rounded-lg bg-ink-panel2 hover:bg-ink-panel text-parchment-dim text-xs font-medium transition"
            >
              Disconnect
            </button>
          </div>
        <% else %>
          <a
            href="/auth/pinterest"
            class="flex-shrink-0 px-4 py-2 rounded-lg bg-red-600 hover:bg-red-500 text-white text-sm font-medium transition"
          >
            Connect
          </a>
        <% end %>
      </div>

      <div class="bg-ink-panel border border-ink-panel2 rounded-xl p-5 flex items-center justify-between gap-4">
        <div class="flex items-center gap-4">
          <div class="w-12 h-12 rounded-xl bg-gradient-to-br from-purple-500 via-pink-500 to-orange-400 flex items-center justify-center flex-shrink-0">
            <img src="/images/instagram-svgrepo-com.svg" class="w-6 h-6 brightness-0 invert" />
          </div>
          <div>
            <p class="text-parchment font-semibold">Instagram</p>
            <p class="text-parchment-dim text-sm">
              {if @instagram_connected,
                do: "Connected — you can post recipes to your Instagram account",
                else: "Connect your account to post recipes to Instagram"}
            </p>
          </div>
        </div>
        <%= if @instagram_connected do %>
          <div class="flex flex-col items-end gap-1.5 flex-shrink-0">
            <span class="flex items-center gap-1.5 text-green-400 text-sm font-medium">
              <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
                <path
                  fill-rule="evenodd"
                  d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z"
                  clip-rule="evenodd"
                />
              </svg>
              Connected
            </span>
            <button
              phx-click="disconnect_social"
              phx-value-provider="instagram"
              data-confirm="Disconnect your Instagram account?"
              class="px-3 py-1.5 rounded-lg bg-ink-panel2 hover:bg-ink-panel text-parchment-dim text-xs font-medium transition"
            >
              Disconnect
            </button>
          </div>
        <% else %>
          <a
            href="/auth/instagram"
            class="flex-shrink-0 px-4 py-2 rounded-lg bg-gradient-to-r from-purple-500 to-pink-500 hover:from-purple-600 hover:to-pink-600 text-white text-sm font-medium transition"
          >
            Connect
          </a>
        <% end %>
      </div>
    </div>
    """
  end

  def get_profile_content(assigns), do: ~H""
end
