defmodule MehungryWeb.RecipeBrowserLive.Index do
  use MehungryWeb, :live_view
  use MehungryWeb.LiveHelpers, :hook_for_update_recipe_details_component
  use MehungryWeb.Presence, :user_tracking

  alias Mehungry.Food
  alias Mehungry.Food.Recipe
  alias Mehungry.Search.RecipeSearchItem
  alias Mehungry.Search
  alias Mehungry.Accounts
  alias Mehungry.Users
  alias Mehungry.Posts
  alias Mehungry.MealBlueprints
  alias Mehungry.PublishedPlans
  alias MehungryWeb.RecipeComponents
  import MehungryWeb.BlueprintComponents

  # Page size for the offset-paginated, condition-prioritized browse mode; kept
  # in step with the cursor paginator's `limit: 10` in `Food.list_recipes/3`.
  @per_page 10

  # Curated nutrient-claim chips on the browse rail — the handful a consumer
  # recognizes. All 22 NRV nutrients stay reachable via `/search/nutrient/:slug`
  # (and `Food.label_for_slug/1`), but only these render as chips and go in the
  # sitemap, to avoid thin micronutrient pages. "High in" tier only.
  @chip_nutrients ["Iron", "Calcium", "Vitamin C", "Potassium", "Magnesium"]
  def chip_nutrients, do: @chip_nutrients

  @impl true
  def mount(params, session, socket) do
    query_str = Map.get(params, "query", "")
    {address, agent} = get_address_agent(socket)
    socket = assign(socket, :address, address)
    socket = assign(socket, :agent, agent)

    referrer =
      case Phoenix.LiveView.get_connect_params(socket) do
        nil -> ""
        cp -> Map.get(cp, "_live_referer", "") || ""
      end

    socket = assign(socket, :referrer, referrer)

    user =
      case is_nil(session["user_token"]) do
        true ->
          nil

        false ->
          Accounts.get_user_by_session_token(session["user_token"])
      end

    {user_profile, user_follows, user_recipes} = Accounts.get_user_essentials(user)

    language =
      socket.assigns[:current_language] || (user_profile && user_profile.language_preference)

    {query, {recipes, cursor_after}} =
      case query_str do
        nil ->
          {query_str, list_recipes(language)}

        qr ->
          Food.search_recipe(qr, language)
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
     |> assign(:active_nutrient, nil)
     |> assign(:pagination_mode, :cursor)
     |> assign(sort_by: "recent")
     |> assign(:must_be_loged_in, nil)
     |> assign(:reply, nil)
     # Diet "mode" derived from the user's saved profile category rules — when set,
     # the default browse feed is filtered to #vegan/#vegetarian and a badge shows.
     # `diet_mode_available` remembers it so the badge can be toggled off/on.
     |> assign(:diet_mode_available, Accounts.diet_mode(user))
     |> assign(:diet_mode, Accounts.diet_mode(user))
     # Browse switches between recipes, public meal-plan blueprints, and
     # published weekly meal plans.
     |> assign(:browse_mode, :recipes)
     |> assign(:blueprint_query, "")
     |> assign(:blueprints, [])
     # Blueprints are loaded lazily the first time the user opens that tab, then
     # kept in assigns so flipping between tabs is a pure presentation switch —
     # no re-query of the DB. An explicit blueprint search still refreshes them.
     |> assign(:blueprints_loaded, false)
     # Published meal plans, loaded lazily the same way as blueprints.
     |> assign(:meal_plan_query, "")
     |> assign(:meal_plans, [])
     |> assign(:meal_plans_loaded, false)
     |> assign_recipe_search()
     |> apply_initial_browse_mode(params)}
  end

  ######################################################################## MESSAGES ############################################################################# 
  @impl true
  def handle_info({MehungryWeb.Onboarding.FormComponent, "profile-saved"}, socket) do
    current_user_profile =
      Accounts.get_user_profile_by_user_id(socket.assigns.current_user.id)

    {:noreply,
     socket
     |> assign(:current_user_profile, current_user_profile)}
  end

  ######################################################################## EVENTS #################################################################################
  @impl true
  def handle_event("set_browse_mode", %{"mode" => "blueprints"}, socket) do
    {:noreply, socket |> ensure_blueprints_loaded() |> assign(:browse_mode, :blueprints)}
  end

  @impl true
  def handle_event("set_browse_mode", %{"mode" => "meal_plans"}, socket) do
    {:noreply, socket |> ensure_meal_plans_loaded() |> assign(:browse_mode, :meal_plans)}
  end

  @impl true
  def handle_event("set_browse_mode", %{"mode" => _}, socket) do
    {:noreply, assign(socket, :browse_mode, :recipes)}
  end

  @impl true
  def handle_event("search_blueprints", %{"query" => query}, socket) do
    blueprints =
      query
      |> MealBlueprints.search_public_blueprints(limit: 60)
      |> MealBlueprints.localize_blueprints(Gettext.get_locale(MehungryWeb.Gettext))

    {:noreply,
     socket
     |> assign(:blueprint_query, query)
     |> assign(:blueprints, blueprints)
     |> assign(:blueprints_loaded, true)}
  end

  @impl true
  def handle_event("search_meal_plans", %{"query" => query}, socket) do
    meal_plans = PublishedPlans.search_public_plans(query, limit: 60)

    {:noreply,
     socket
     |> assign(:meal_plan_query, query)
     |> assign(:meal_plans, meal_plans)
     |> assign(:meal_plans_loaded, true)}
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

    language = get_user_language(socket)
    {:noreply, stream_recipes(socket, list_recipes(language))}
  end

  @impl true
  def handle_event("close-modal", _thing, socket) do
    {:noreply, push_patch(socket, to: "/browse")}
  end

  @impl true
  def handle_event("keep_browsing", _thing, socket) do
    {:noreply, assign(socket, :must_be_loged_in, nil)}
  end

  # Turn the diet-mode filter off (see everything) or back on, then re-run the
  # current search so the feed reflects it immediately.
  @impl true
  def handle_event("toggle_diet_mode", _params, socket) do
    new_mode = if socket.assigns.diet_mode, do: nil, else: socket.assigns.diet_mode_available

    socket = assign(socket, :diet_mode, new_mode)
    {:noreply, handle_search(socket, socket.assigns.query_string)}
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
        user_recipes = Users.list_user_saved_recipe_ids(socket.assigns.current_user)
        socket = assign(socket, :user_recipes, user_recipes)
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("load-more", _, socket) do
    language = get_user_language(socket)
    next_page = socket.assigns.page + 1

    socket =
      case Map.get(socket.assigns, :pagination_mode, :cursor) do
        # Condition-prioritized browse: one ordered list, offset-paginated by
        # page number so the computed "encouraged first" order is preserved.
        :offset ->
          recipes =
            Food.list_recipes_page(
              Map.get(socket.assigns, :query),
              next_page,
              @per_page,
              language
            )

          stream_recipes(socket, recipes)

        # Default browse / search: keep the cursor paginator.
        _ ->
          case Map.get(socket.assigns, :cursor_after) do
            nil ->
              socket

            cursor_after ->
              {recipes, cursor_after} =
                Food.list_recipes(cursor_after, Map.get(socket.assigns, :query), language)

              socket
              |> assign(:cursor_after, cursor_after)
              |> stream_recipes(recipes)
          end
      end

    # Always advance the page counter so the InfiniteScroll hook re-arms, even on
    # a terminal (no-op) load — matching the previous always-increment behavior.
    {:noreply, assign(socket, :page, next_page)}
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
        dest =
          cond do
            String.at(query_string, 0) == "#" ->
              "/search/hashtag/" <> String.slice(query_string, 1..-1//1)

            String.at(query_string, 0) == "@" ->
              "/search/ingredient/" <> URI.encode(String.slice(query_string, 1..-1//1))

            true ->
              "/search/" <> query_string
          end

        socket = MehungryWeb.GoogleAnalytics.track(socket, "search", %{search_term: query_string})

        {:noreply, Phoenix.LiveView.push_navigate(socket, to: dest)}
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
        recipes = Search.search_recipe(recipe_search_item.query_string, get_user_language(socket))

        {:noreply,
         socket
         |> stream_recipes(recipes, reset: true)
         |> assign(:changeset, changeset)}
    end
  end

  ###################################################################################### ACTIONS ########################################################

  @impl true
  def handle_params(params, uri, socket) do
    socket = assign(socket, :path, uri)
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  # Opens the browse page straight to a non-default tab (so a "back to Meal Plans"
  # link lands on meal plans, not the Recipes default). Mirrors `set_browse_mode`
  # but driven by the `?mode=` URL param on mount.
  defp apply_initial_browse_mode(socket, %{"mode" => "meal_plans"}),
    do: socket |> ensure_meal_plans_loaded() |> assign(:browse_mode, :meal_plans)

  defp apply_initial_browse_mode(socket, %{"mode" => "blueprints"}),
    do: socket |> ensure_blueprints_loaded() |> assign(:browse_mode, :blueprints)

  defp apply_initial_browse_mode(socket, _params), do: socket

  # Lazy-load the tab's rows once, then keep them in assigns so flipping tabs is a
  # pure presentation switch (no re-query). Shared by the tab event and mount's
  # initial-mode opener.
  defp ensure_blueprints_loaded(%{assigns: %{blueprints_loaded: true}} = socket), do: socket

  defp ensure_blueprints_loaded(socket) do
    blueprints =
      socket.assigns.blueprint_query
      |> MealBlueprints.search_public_blueprints(limit: 60)
      |> MealBlueprints.localize_blueprints(Gettext.get_locale(MehungryWeb.Gettext))

    socket
    |> assign(:blueprints, blueprints)
    |> assign(:blueprints_loaded, true)
  end

  defp ensure_meal_plans_loaded(%{assigns: %{meal_plans_loaded: true}} = socket), do: socket

  defp ensure_meal_plans_loaded(socket) do
    meal_plans = PublishedPlans.search_public_plans(socket.assigns.meal_plan_query, limit: 60)

    socket
    |> assign(:meal_plans, meal_plans)
    |> assign(:meal_plans_loaded, true)
  end

  defp assign_user_meta(socket) do
    user = socket.assigns.current_user

    profile =
      case is_nil(user) do
        true ->
          nil

        false ->
          Accounts.get_user_profile_by_user_id(user.id)
      end

    user_recipes =
      case is_nil(user) do
        true ->
          []

        false ->
          Users.list_user_saved_recipe_ids(user)
      end

    socket
    |> assign(:user_recipes, user_recipes)
    |> assign(:user_profile, profile)
  end

  defp handle_search(socket, query_str) do
    language = get_user_language(socket)

    {query, pagination_mode, {recipes, cursor_after}} =
      cond do
        is_binary(query_str) and String.at(query_str, 0) == "#" ->
          {query, page} = Food.search_hashtag1(query_str)
          {query, :cursor, page}

        is_binary(query_str) and String.at(query_str, 0) == "@" ->
          {query, page} = Food.search_recipes_by_ingredient(String.slice(query_str, 1..-1//1))
          {query, :cursor, page}

        is_nil(query_str) ->
          # Default browse feed. If the user is in a diet mode, filter it to that
          # diet's hashtag; otherwise show everything. An explicit search (#/@/text/
          # condition) above overrides diet mode — the user asked for something specific.
          case socket.assigns[:diet_mode] do
            mode when mode in [:vegan, :vegetarian] ->
              {query, page} = Food.search_hashtag1("#" <> Atom.to_string(mode))
              {query, :cursor, page}

            _ ->
              {query_str, :cursor, list_recipes(language)}
          end

        true ->
          {query, page} = Food.search_recipe(query_str, language)
          {query, :cursor, page}
      end

    socket
    |> assign(:cursor_after, cursor_after)
    |> assign(:query_string, query_str)
    |> assign(:query, query)
    |> assign(:pagination_mode, pagination_mode)
    |> assign(:search_changeset, nil)
    # Any text/#/@/default search clears the nutrient-chip highlight; the nutrient
    # filter (apply_action below) is the only path that sets it.
    |> assign(:active_nutrient, nil)
    |> stream_recipes(recipes, reset: true)
    |> assign(:not_empty, length(recipes) > 0)
  end

  # Pre-defined nutrient-claim filter ("foods high in iron"), reached by the
  # crawlable `/search/nutrient/:slug` route and the browse chip rail. Reuses the
  # same composable-query + cursor-stream machinery as the #/@ searches, driven by
  # the persisted `recipes.badges` column via `Food.search_recipes_by_badge/3`.
  defp apply_action(socket, :index, %{"nutrient" => slug} = _params) do
    case Food.label_for_slug(slug) do
      nil ->
        # Unknown nutrient slug → fall back to the default browse feed.
        apply_action(socket, :index, %{})

      label ->
        language = get_user_language(socket)
        {query, {recipes, cursor_after}} = Food.search_recipes_by_badge(label, "high", language)
        maybe_track_user(%{query: "nutrient:" <> slug}, socket)

        socket
        |> assign(:recipe, nil)
        |> assign_user_meta()
        |> assign(:cursor_after, cursor_after)
        |> assign(:query, query)
        |> assign(:query_string, nil)
        |> assign(:pagination_mode, :cursor)
        |> assign(:search_changeset, nil)
        |> assign(:active_nutrient, label)
        |> stream_recipes(recipes, reset: true)
        |> assign(:not_empty, length(recipes) > 0)
        |> assign(:return_to, Map.get(socket.assigns, :path, ~p"/browse"))
        |> assign(:page, 1)
        |> assign(:page_title, "High-#{label} Recipes | M3Hungry")
        |> assign(
          :page_description,
          "Browse recipes that are high in #{label} — each badge is the EU per-serving" <>
            " nutrition claim (Reg. 1169/2011 & 1924/2006), computed from USDA data on M3Hungry."
        )
    end
  end

  defp apply_action(socket, :index, %{"ingredient" => ingredient_name} = _params) do
    maybe_track_user(%{query: "@" <> ingredient_name}, socket)

    socket
    |> assign(:recipe, nil)
    |> assign_user_meta()
    |> handle_search("@" <> ingredient_name)
    |> assign(:return_to, Map.get(socket.assigns, :path, ~p"/browse"))
    |> assign(:page, 1)
    |> assign(:page_title, "Recipes with #{ingredient_name} | M3Hungry")
    |> assign(
      :page_description,
      "Browse recipes containing #{ingredient_name} with full USDA nutrition data on M3Hungry."
    )
  end

  defp apply_action(socket, :index, %{"hashtag" => query_str} = _params) do
    maybe_track_user(%{query: query_str}, socket)
    display_tag = if String.starts_with?(query_str, "#"), do: query_str, else: "#" <> query_str

    socket
    |> assign(:recipe, nil)
    |> assign_user_meta()
    |> handle_search(display_tag)
    |> assign(:return_to, Map.get(socket.assigns, :path, ~p"/browse"))
    |> assign(:page, 1)
    |> assign(:page_title, "#{display_tag} Recipes | M3Hungry")
    |> assign(
      :page_description,
      "Browse #{display_tag} recipes with complete USDA nutrition data. Discover ingredients, macros, and cooking instructions on M3Hungry."
    )
  end

  defp apply_action(socket, :index, %{"query" => query_str} = _params) do
    maybe_track_user(%{query: query_str}, socket)

    socket
    |> assign(:recipe, nil)
    |> assign_user_meta()
    |> handle_search(query_str)
    |> assign(:return_to, Map.get(socket.assigns, :path, ~p"/browse"))
    |> assign(:page, 1)
    |> assign(:page_title, "\"#{query_str}\" Recipes | M3Hungry")
    |> assign(
      :page_description,
      "Search results for '#{query_str}' — browse recipes with USDA nutrition analysis, macros, and step-by-step instructions on M3Hungry."
    )
  end

  defp apply_action(socket, :index, _pars) do
    maybe_track_user(%{query: ""}, socket)

    socket =
      socket
      |> assign(:recipe, nil)
      |> assign(:page, 1)
      |> assign(:page_title, "Browse Recipes")
      |> assign(
        :page_description,
        "Browse thousands of recipes with complete USDA nutrition data. Discover new dishes, track macros, and plan your meals on M3Hungry."
      )
      |> assign_user_meta()
      |> handle_search(nil)
      |> assign(:return_to, Map.get(socket.assigns, :path, ~p"/browse"))

    assign(socket, :search_changeset, nil)
  end

  defp apply_action(socket, :show_recipe, %{"id" => id}) do
    recipe = Food.get_recipe!(id, get_user_language(socket))

    if !is_nil(recipe) do
      Posts.subscribe_to_recipe(%{recipe_id: id})

      user = socket.assigns.current_user

      socket =
        if is_nil(Map.get(socket.assigns, :return_to, nil)) do
          assign(socket, :return_to, ~p"/browse")
        else
          socket
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
        socket
        |> assign(:recipe, recipe)
        |> MehungryWeb.RecipeSeo.assign(recipe)
        |> assign(:user_recipes, user_recipes)
        |> stream(:recipes, [])

      maybe_track_user(%{page: "browser", type: :show_recipe, recipe: recipe}, socket)
      socket
    else
      socket |> put_flash(:error, "Recipe not found") |> push_navigate(to: "/home")
    end
  end

  defp apply_action(socket, :show, %{"id" => id}) do
    recipe = Food.get_recipe!(id, get_user_language(socket))
    maybe_track_user(recipe, socket)

    query_str = ""
    language = get_user_language(socket)

    {_query, {recipes, cursor_after}} = Food.search_recipe(query_str, language)

    socket
    |> assign(:nutrients, recipe.nutrients)
    |> assign(:primary_size, recipe.primary_nutrients_size)
    |> assign(:recipe, recipe)
    |> assign(:query_string, "")
    |> stream_recipes(recipes)
    |> assign(:cursor_after, cursor_after)
    |> assign(:page_title, recipe.title)
    |> assign(:page_seo_data, %{
      title: recipe.title,
      img: recipe.image_url,
      id: Integer.to_string(recipe.id)
    })
  end

  ###################################################################################### UTILS #################################################################

  def assign_recipe_search(socket) do
    socket
    |> assign(:recipe_search_item, %RecipeSearchItem{})
  end

  defp stream_recipes(socket, recipes, opts \\ []) do
    stream(socket, :recipes, recipes, opts)
  end

  def assign_changeset(%{assigns: %{recipe_search_item: recipe_search_item}} = socket) do
    socket
    |> assign(:search_changeset, Search.change_recipe_search_item(recipe_search_item))
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

  defp list_recipes(language \\ nil) do
    {result, cursor_after} = Food.list_recipes(nil, nil, language)

    result =
      Enum.map(result, fn %Recipe{} = recipe ->
        %Recipe{recipe | recipe_image_remote: recipe.image_url}
      end)

    {result, cursor_after}
  end

  defp get_user_language(socket) do
    # The URL locale (set from `/:locale/…` via RestoreLocale) is authoritative;
    # fall back to the stored profile preference only when it's absent.
    profile =
      Map.get(socket.assigns, :current_user_profile) || Map.get(socket.assigns, :user_profile)

    socket.assigns[:current_language] || (profile && profile.language_preference)
  end
end
