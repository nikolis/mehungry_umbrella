defmodule MehungryWeb.RecipeDetailsComponent do
  use MehungryWeb, :live_component

  import MehungryWeb.CoreComponents
  import MehungryWeb.RecipeComponents

  alias Mehungry.Posts.Comment
  alias Mehungry.{Posts, Users, Food, Accounts, Subscriptions}
  alias Mehungry.Social.Facebook
  alias MehungryWeb.InsightGraphicGenerator
  alias Phoenix.LiveView.AsyncResult

  embed_templates("components/*")
  @color_fill "#00A0D0"

  # cancel_comment_reply
  @impl true
  def handle_event("cancel_comment_reply", _, socket) do
    socket =
      socket
      |> assign(:reply, nil)

    {:noreply, socket}
  end

  @impl true
  def handle_event("generate_graphic", _params, socket) do
    recipe = socket.assigns.recipe
    user = socket.assigns.current_user

    cond do
      is_nil(user) ->
        {:noreply, assign(socket, :must_be_loged_in, 1)}

      Subscriptions.check_quota(user.id, "graphic_generation") == {:error, :quota_exceeded} ->
        {:noreply,
         assign(
           socket,
           :graphic_error,
           "You've used all your graphic generations this month. Upgrade for more."
         )}

      true ->
        recipe_id = recipe.id
        user_id = user.id

        {:noreply,
         socket
         |> assign(:graphic_running, true)
         |> assign(:graphic_result, nil)
         |> assign(:graphic_error, nil)
         |> start_async(:insight_graphic, fn ->
           InsightGraphicGenerator.generate(recipe_id, user_id)
         end)}
    end
  end

  @impl true
  def handle_async(:insight_graphic, {:ok, {:ok, graphic}}, socket) do
    {:noreply,
     socket
     |> assign(:graphic_running, false)
     |> assign(:graphic_result, graphic)
     |> assign(:graphic_error, nil)}
  end

  @impl true
  def handle_async(:insight_graphic, {:ok, {:error, _reason}}, socket) do
    {:noreply,
     socket
     |> assign(:graphic_running, false)
     |> assign(:graphic_error, "Graphic generation failed. Please try again.")}
  end

  @impl true
  def handle_async(:insight_graphic, {:exit, _reason}, socket) do
    {:noreply,
     socket
     |> assign(:graphic_running, false)
     |> assign(:graphic_error, "Graphic generation failed. Please try again.")}
  end

  @impl true
  def handle_event("post-on-facebook", %{"recipe_id" => recipe_id, "user_id" => user_id}, socket) do
    recipe = recipe_id |> Food.get_recipe!() |> Food.recipe_with_share_image()
    user = Accounts.get_user!(user_id)

    Facebook.post_recipe_container(user, recipe, %{})

    socket =
      socket
      |> assign(:reply, nil)

    {:noreply, socket}
  end

  @impl true
  def handle_event("post-on-instagram", %{"recipe_id" => recipe_id, "user_id" => user_id}, socket) do
    recipe = recipe_id |> Food.get_recipe!() |> Food.recipe_with_share_image()
    user = Accounts.get_user!(user_id)
    Mehungry.Social.Instagram.post_recipe(user, recipe)

    socket =
      socket
      |> assign(:reply, nil)

    {:noreply, socket}
  end

  @impl true
  def handle_event("add-reply-form", %{"id" => comment_id}, socket) do
    case is_nil(socket.assigns.current_user) do
      true ->
        socket = assign(socket, :must_be_loged_in, 1)
        {:noreply, socket}

      false ->
        {comment_id, _} = Integer.parse(comment_id)

        socket =
          socket
          |> assign(:reply, %{comment_id: comment_id})

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event(
        "vote_comment",
        %{"id" => comment_id, "reaction" => reaction} = _params,
        socket
      ) do
    case is_nil(socket.assigns.current_user) do
      true ->
        socket = assign(socket, :must_be_loged_in, 1)
        {:noreply, socket}

      false ->
        {comment_id, _} = Integer.parse(comment_id)

        # socket =
        # socket
        # |> assign(:reply, %{comment_id: comment_id})

        Mehungry.Posts.vote_comment(comment_id, socket.assigns.current_user.id, reaction)

        {:noreply, socket}
    end
  end

  def get_positive_votes(votes) do
    Enum.reduce(votes, 0, fn x, acc ->
      case x.positive do
        true ->
          acc + 1

        false ->
          acc
      end
    end)
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

  def get_style2(item_list, user, positive) do
    has =
      case is_nil(user) or is_nil(item_list) or Enum.empty?(item_list) do
        true ->
          false

        false ->
          Enum.any?(item_list, fn x -> x.user_id == user.id and x.positive == positive end)
      end

    case has do
      true ->
        @color_fill

      false ->
        "#FFFFFF"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="recipe_presentation_modal"
      phx-hook="RecipeDetailTimer"
      class="recipe-details-page min-h-screen bg-ink text-parchment pb-10"
    >
      <div class=" mx-auto px-4 py-8 max-w-4xl">
        <div class="w-full">
          <!-- Hero Section -->
          <div class="bg-ink-panel rounded-2xl overflow-hidden border border-ink-panel2 mb-8">
            <!-- Image -->
            <div class="relative aspect-video bg-ink-panel2">
              <%= if @recipe.image_url do %>
                <img src={@recipe.image_url} alt={@recipe.title} class="w-full h-full object-cover" />
              <% else %>
                <div class="w-full h-full flex items-center justify-center">
                  <svg
                    class="w-20 h-20 text-parchment-dim"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"
                    />
                  </svg>
                </div>
              <% end %>
              <.recipe_like_container
                type="browse"
                user_recipes={@user_recipes}
                recipe={@recipe}
                current_user={@current_user}
                id={@id <> "like_container"}
                myself={@myself}
              />
              <%= if @recipe.image_url do %>
                <button
                  type="button"
                  phx-click="generate_graphic"
                  phx-target={@myself}
                  disabled={@graphic_running}
                  class="absolute bottom-3 right-3 flex items-center gap-1.5 px-3 py-1.5 rounded-full bg-paprika/90 hover:bg-paprika disabled:opacity-60 text-white font-semibold text-xs shadow-lg backdrop-blur transition-colors"
                >
                  <.icon
                    name={if @graphic_running, do: "hero-arrow-path", else: "hero-sparkles"}
                    class={"w-4 h-4 #{if @graphic_running, do: "animate-spin"}"}
                  />
                  {if @graphic_running, do: "Creating graphic…", else: "Shareable graphic"}
                </button>
              <% end %>
            </div>

            <div :if={@graphic_error} class="mx-6 mt-4 rounded-lg bg-red-900/40 border border-red-700 text-red-200 text-xs px-3 py-2">
              {@graphic_error}
            </div>

            <div :if={@graphic_result} class="mx-6 mt-4 rounded-xl bg-ink border border-ink-panel2 p-3 flex gap-3">
              <img
                src={@graphic_result.image_url}
                alt="Shareable insight graphic"
                class="w-28 h-28 rounded-lg object-cover shrink-0"
              />
              <div class="min-w-0 flex flex-col">
                <p class="text-parchment text-sm font-semibold">{@graphic_result.headline}</p>
                <p class="text-parchment-dim text-xs mt-1 line-clamp-3">{@graphic_result.caption}</p>
                <a
                  href={@graphic_result.image_url}
                  target="_blank"
                  rel="noopener"
                  class="mt-auto inline-flex items-center gap-1.5 text-paprika hover:text-paprika-soft text-xs font-semibold"
                >
                  <.icon name="hero-arrow-down-tray" class="w-3.5 h-3.5" /> Download to share
                </a>
              </div>
            </div>
            <!-- Content -->
            <div class="p-6">
              <h1 class="text-2xl md:text-3xl font-display font-medium text-parchment mb-2">
                {@recipe.title}
              </h1>
              <p class="text-parchment-dim mb-4">{@recipe.description}</p>

              <% nutrient_badges = MehungryWeb.RecipeComponents.high_badges(@recipe, 99) %>
              <% badge_limit = 4 %>
              <div :if={nutrient_badges != []} class="flex flex-wrap items-center gap-2 mb-4">
                <span
                  :for={{badge, index} <- Enum.with_index(nutrient_badges)}
                  class={[
                    "rounded-full bg-paprika/15 text-paprika-soft border border-paprika/30 text-xs font-semibold px-3 py-1",
                    index >= badge_limit && "hidden recipe-badge-extra-#{@recipe.id}"
                  ]}
                  title={gettext("Claims follow EU Reg. 1169/2011 & 1924/2006, per serving.")}
                >
                  {MehungryWeb.NutrientLabels.claim_label(badge["nutrient"])} · {badge["percent_nrv"]}% NRV
                </span>
                <button
                  :if={length(nutrient_badges) > badge_limit}
                  type="button"
                  phx-click={
                    JS.toggle_class("hidden", to: ".recipe-badge-extra-#{@recipe.id}")
                    |> JS.toggle_class("hidden", to: "#recipe-badge-more-#{@recipe.id}")
                    |> JS.toggle_class("hidden", to: "#recipe-badge-less-#{@recipe.id}")
                  }
                  class="text-paprika-soft hover:text-paprika text-xs font-semibold px-2 py-1 underline underline-offset-2"
                >
                  <span id={"recipe-badge-more-#{@recipe.id}"}>
                    {gettext("Show %{count} more", count: length(nutrient_badges) - badge_limit)}
                  </span>
                  <span id={"recipe-badge-less-#{@recipe.id}"} class="hidden">
                    {gettext("Show less")}
                  </span>
                </button>
              </div>

              <.recipe_tags recipe={@recipe} />

              <!-- Recipe Stats -->
              <div class="flex flex-wrap gap-4 mb-6">
                <div class="flex items-center gap-2">
                  <svg
                    class="w-5 h-5 text-parchment-dim"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"
                    />
                  </svg>
                  <span class="font-bold text-basil [font-variant-numeric:tabular-nums]">
                    {@recipe.cooking_time_lower_limit + @recipe.preperation_time_lower_limit}
                  </span>
                  <span class="text-parchment-dim">min total</span>
                  <span class="text-parchment-dim text-sm">
                    (Prep:
                    <span class="font-bold text-basil [font-variant-numeric:tabular-nums]">{@recipe.preperation_time_lower_limit}</span>
                    | Cook: <span class="font-bold text-basil [font-variant-numeric:tabular-nums]">{@recipe.cooking_time_lower_limit}</span>)
                  </span>
                </div>
                <div class="flex items-center gap-2">
                  <svg
                    class="w-5 h-5 text-parchment-dim"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197M13 7a4 4 0 11-8 0 4 4 0 018 0z"
                    />
                  </svg>
                  <span class="font-bold text-basil [font-variant-numeric:tabular-nums]">{@recipe.servings}</span>
                  <span class="text-parchment-dim">servings</span>
                </div>
                <div class="flex items-center gap-2">
                  <%= case @recipe.difficulty do %>
                    <% "Easy" -> %>
                      <svg
                        class="w-5 h-5 text-green-500"
                        fill="none"
                        stroke="currentColor"
                        viewBox="0 0 24 24"
                      >
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          stroke-width="2"
                          d="M5 13l4 4L19 7"
                        />
                      </svg>
                    <% "Medium" -> %>
                      <svg
                        class="w-5 h-5 text-yellow-500"
                        fill="none"
                        stroke="currentColor"
                        viewBox="0 0 24 24"
                      >
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          stroke-width="2"
                          d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"
                        />
                      </svg>
                    <% _ -> %>
                      <svg
                        class="w-5 h-5 text-red-500"
                        fill="none"
                        stroke="currentColor"
                        viewBox="0 0 24 24"
                      >
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          stroke-width="2"
                          d="M6 18L18 6M6 6l12 12"
                        />
                      </svg>
                  <% end %>
                  <span class="text-parchment">{@recipe.difficulty}</span>
                </div>
              </div>
              <!-- Author Section -->
              <div class="flex items-center justify-between p-4 border border-ink-panel2 bg-black/20 rounded-xl">
                <div class="flex items-center gap-3">
                  <img
                    src={@recipe.user.profile_pic}
                    alt={@recipe.user.name}
                    class="w-12 h-12 rounded-full object-cover"
                  />
                  <div>
                    <a
                      href={"/profile/#{@recipe.user.id}"}
                      class="text-parchment font-semibold hover:text-paprika-soft transition"
                    >
                      {@recipe.user.name}
                    </a>
                    <p class="text-parchment-dim text-sm">
                      <span class="font-bold text-basil [font-variant-numeric:tabular-nums]">{5}</span>
                      recipes
                    </p>
                  </div>
                </div>
                <%= if !is_nil(@current_user) do %>
                  <button
                    phx-click="save_user_follow"
                    phx-value-follow_id={@recipe.user.id}
                    class={[
                      "px-4 py-2 rounded-lg font-bold transition",
                      (@recipe.user.id not in @user_follows &&
                         "text-parchment-dim hover:text-parchment") ||
                        "bg-paprika hover:bg-paprika-soft text-ink"
                    ]}
                  >
                    {if @recipe.user.id not in @user_follows, do: "Following", else: "Follow"}
                  </button>
                <% else %>
                  <a
                    href="/users/log_in"
                    class="px-4 py-2 rounded-lg font-bold transition bg-paprika hover:bg-paprika-soft text-ink rounded-full"
                  >
                    Follow
                  </a>
                <% end %>
              </div>
            </div>
          </div>
        </div>
        <div class="w-full mt-2">
          <div class="mt-8">
            <.recipe_details
              recipe={@recipe}
              current_user={@current_user}
              nutrients={@recipe.nutrients}
              primary_size={@recipe.primary_nutrients_size}
              locale={Gettext.get_locale(MehungryWeb.Gettext)}
              ingredient_display_names={@ingredient_display_names}
            />
          </div>
          <%!-- "Nutrition Insights" (nutrient-interaction panel) is HIDDEN for now.
               The underlying biochemistry rules are sound, but the recipe-level
               inference is low-signal/occasionally misleading because it keys on
               each ingredient's per-100g nutrient density rather than the amount
               actually used in the dish (and ignores iron type, dose ratios, meal
               timing). See docs/food/nutrient_interactions.md for the full
               write-up and accuracy assessment. @interactions is forced to [] in
               maybe_load_recipe_async/3 so nothing renders and no query runs;
               un-comment this block and restore the query to re-enable. --%>
          <%!--
          <.async_result :let={interactions} assign={@interactions}>
            <:loading>
              <div class="mt-20 animate-pulse">
                <div class="h-6 w-40 rounded bg-ink-panel2 mb-4"></div>
                <div class="h-16 rounded-xl bg-ink-panel2"></div>
              </div>
            </:loading>
            <:failed :let={_reason}></:failed>
            <%= if interactions != [] do %>
              <div class="mt-20">
                <h2 class="text-lg font-display font-medium text-parchment mb-4">
                  Nutrition Insights
                </h2>
                <.nutrient_interaction_panel interactions={interactions} />
              </div>
            <% end %>
          </.async_result>
          --%>

          <div
            class="mt-20 bg-ink-panel rounded-xl border border-ink-panel2 overflow-hidden"
            id="comments"
          >
            <button
              class="w-full flex justify-between items-center p-4 hover:bg-black/20 transition relative"
              phx-click={JS.toggle_class("h-0 overflow-hidden mt-6", to: ".comment")}
            >
              <h3 class="text-parchment font-semibold">
                <.async_result :let={comments} assign={@recipe_comments}>
                  <:loading>Comments</:loading>
                  <:failed :let={_reason}>Comments</:failed>
                  {"Comments (#{length(comments)})"}
                </.async_result>
              </h3>

              <svg
                class={[
                  "w-5 h-5 text-parchment-dim transition-transform"
                ]}
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M19 9l-7 7-7-7"
                />
              </svg>
            </button>
            <div class="comment h-0 overflow-hidden">
              <%= if !is_nil(@current_user) do %>
                <.live_component
                  module={MehungryWeb.RecipeDetailsLive.FormComponentComment}
                  id="comment_form"
                  title={@page_title}
                  action={@live_action}
                  current_user={@current_user}
                  comment={@comment}
                />
              <% end %>
              <.async_result :let={comments} assign={@recipe_comments}>
                <:loading>
                  <div class="text-center py-8 text-parchment-dim">Loading comments…</div>
                </:loading>
                <:failed :let={_reason}>
                  <div class="text-center py-8 text-parchment-dim">
                    Couldn't load comments.
                  </div>
                </:failed>
                <%= if Enum.empty?(comments) do %>
                  <div class="text-center py-8 text-parchment-dim">
                    No comments yet. Be the first to comment!
                  </div>
                <% else %>
                  <div class="mt-2">
                    <%= for comment <- comments do %>
                      <.comment
                        comment={comment}
                        user={comment.user}
                        current_user={@current_user}
                        live_action={@live_action}
                        page_title={@page_title}
                        myself={@myself}
                        reply={@reply}
                      />
                    <% end %>
                  </div>
                <% end %>
              </.async_result>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def handle_info(%{new_vote: vote, type_: _type_}, socket) do
    post = Posts.get_post!(vote.post_id)

    posts =
      Enum.map(socket.assigns.posts, fn x ->
        case x.id == post.id do
          false ->
            x

          true ->
            post
        end
      end)

    socket =
      socket
      |> assign(:posts, posts)

    {:noreply, socket}
  end

  def handle_info(%{new_comment: comment}, socket) do
    recipe_comments = socket.assigns.recipe_comments
    comment = Posts.get_comment!(comment.id)

    comments =
      Enum.into(Enum.filter(recipe_comments, fn x -> x.id != comment.id end), [comment])
      |> Enum.sort_by(& &1.updated_at)

    socket =
      socket
      |> assign(:recipe_comments, comments)

    {:noreply, socket}
  end

  @doc """
    Every LiveView that uses this component is also importing 
    MehungryWeb.LiveHelpers, :hook_for_update_recipe_details_component
    behaviour so this update is here to handle the updates by this behaviour
    so as not to make a mess with the "typical" update 
  """
  @impl true
  def update(%{reply: nil} = assigns, socket) do
    reply = Map.get(assigns, :reply, nil)
    socket = assign(socket, :reply, reply)

    {:ok, socket}
  end

  @impl true
  def update(%{recipe_comments: recipe_comments} = _assigns, socket) do
    # Live comment updates arrive as a plain list; fold it into the AsyncResult
    # the template renders so a new/edited comment shows without a re-fetch.
    async =
      case socket.assigns[:recipe_comments] do
        %AsyncResult{} = ar -> AsyncResult.ok(ar, recipe_comments)
        _ -> AsyncResult.ok(recipe_comments)
      end

    {:ok, assign(socket, :recipe_comments, async)}
  end

  @impl true
  def update(assigns, socket) do
    user_follows =
      if(is_nil(Map.get(assigns, :user_follows))) do
        []
      else
        assigns.user_follows
      end

    reply = Map.get(assigns, :reply, nil)

    ingredient_ids =
      assigns.recipe.recipe_ingredients
      |> Enum.map(& &1.ingredient_id)

    profile =
      case assigns.current_user do
        nil -> nil
        user -> Accounts.get_user_profile_by_user_id(user.id)
      end

    user_language = (profile && profile.language_preference) || assigns.recipe.language_name

    display_names =
      Food.ingredient_display_names(ingredient_ids, user_language)

    socket =
      socket
      |> assign(assigns)
      |> assign(:recipe, assigns.recipe)
      |> assign(:reply, reply)
      |> assign(:user_follows, user_follows)
      |> assign(:ingredient_display_names, display_names)
      |> assign_new(:graphic_running, fn -> false end)
      |> assign_new(:graphic_result, fn -> nil end)
      |> assign_new(:graphic_error, fn -> nil end)
      |> assign(
        :comment,
        get_when_first_exists(assigns.current_user, fn ->
          %Comment{user_id: assigns.current_user.id, recipe_id: assigns.recipe.id}
        end)
      )
      |> maybe_load_recipe_async(assigns.recipe, ingredient_ids)

    {:ok, socket}
  end

  # Comments and nutrient interactions are below the fold (comments even start
  # collapsed), so they load asynchronously: the modal paints immediately with
  # the recipe, ingredients and flags, then these fill in. Guarded to load once
  # per recipe so a routine parent re-render doesn't reset them to a spinner or
  # re-run the queries. The live comment-update path (send_update with
  # `%{recipe_comments: ...}`) refreshes the list without going through here.
  defp maybe_load_recipe_async(socket, recipe, _ingredient_ids) do
    if socket.assigns[:async_recipe_id] == recipe.id do
      socket
    else
      recipe_id = recipe.id

      socket
      |> assign(:async_recipe_id, recipe_id)
      |> assign_async(:recipe_comments, fn ->
        {:ok, %{recipe_comments: Food.get_recipe_comments(recipe_id)}}
      end)
      # "Nutrition Insights" (nutrient-interaction panel) is HIDDEN for now — its
      # recipe-level inference is low-signal/occasionally misleading (it keys on
      # per-100g ingredient density, not the amount actually used). See
      # docs/food/nutrient_interactions.md. Return [] so the panel renders nothing
      # and we skip the DB query; to re-enable, restore the call below and un-hide
      # the render block (search "Nutrition Insights").
      #   Food.get_interactions_for_ingredients(ingredient_ids)
      |> assign_async(:interactions, fn -> {:ok, %{interactions: []}} end)
    end
  end
end
