defmodule MehungryWeb.RecipeDetailsComponent do
  use MehungryWeb, :live_component

  import MehungryWeb.CoreComponents
  import MehungryWeb.RecipeComponents

  alias Mehungry.Posts.Comment
  alias Mehungry.{Posts, Users, Food, Accounts}
  alias Mehungry.Api.Instagram
  alias Mehungry.Api.Facebook

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
  def handle_event("post-on-facebook", %{"recipe_id" => recipe_id, "user_id" => user_id}, socket) do
    recipe = Food.get_recipe!(recipe_id)
    user = Accounts.get_user!(user_id)

    Facebook.post_recipe_container(user, recipe)

    socket =
      socket
      |> assign(:reply, nil)

    {:noreply, socket}
  end

  @impl true
  def handle_event("post-on-instagram", %{"recipe_id" => recipe_id, "user_id" => user_id}, socket) do
    recipe = Food.get_recipe!(recipe_id)
    user = Accounts.get_user!(user_id)
    Instagram.post_recipe_container(user, recipe)

    socket =
      socket
      |> assign(:reply, nil)

    {:noreply, socket}
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

        user_recipes =
          Users.list_user_saved_recipe_ids(socket.assigns.user)

        socket = assign(socket, :user_recipes, user_recipes)
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("add-reply-form", %{"id" => comment_id}, socket) do
    case is_nil(socket.assigns.user) do
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
    case is_nil(socket.assigns.user) do
      true ->
        socket = assign(socket, :must_be_loged_in, 1)
        {:noreply, socket}

      false ->
        {comment_id, _} = Integer.parse(comment_id)

        # socket =
        # socket
        # |> assign(:reply, %{comment_id: comment_id})

        Mehungry.Posts.vote_comment(comment_id, socket.assigns.user.id, reaction)

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
      data-server-ms={@server_ms}
      data-recipe-id={@recipe.id}
      class="min-h-screen bg-slate-900 pb-10"
    >
      <div class=" mx-auto px-4 py-8 max-w-4xl">
        <div class="w-full">
          <!-- Hero Section -->
          <div class="bg-slate-800 rounded-2xl overflow-hidden border border-slate-700 mb-8">
            <!-- Image -->
            <div class="relative aspect-video bg-slate-700">
              <%= if @recipe.image_url do %>
                <img src={@recipe.image_url} alt={@recipe.title} class="w-full h-full object-cover" />
              <% else %>
                <div class="w-full h-full flex items-center justify-center">
                  <svg
                    class="w-20 h-20 text-slate-500"
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
            </div>
            <!-- Content -->
            <div class="p-6">
              <h1 class="text-2xl md:text-3xl font-bold text-white mb-2">{@recipe.title}</h1>
              <p class="text-slate-400 mb-4">{@recipe.description}</p>
              
    <!-- Recipe Stats -->
              <div class="flex flex-wrap gap-4 mb-6">
                <div class="flex items-center gap-2">
                  <svg
                    class="w-5 h-5 text-slate-500"
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
                  <span class="text-slate-300">
                    {@recipe.cooking_time_lower_limit + @recipe.preperation_time_lower_limit} min total
                  </span>
                  <span class="text-slate-500 text-sm">
                    (Prep: {@recipe.preperation_time_lower_limit} | Cook: {@recipe.cooking_time_lower_limit})
                  </span>
                </div>
                <div class="flex items-center gap-2">
                  <svg
                    class="w-5 h-5 text-slate-500"
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
                  <span class="text-slate-300">{@recipe.servings} servings</span>
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
                  <span class="text-slate-300">{@recipe.difficulty}</span>
                </div>
              </div>
              <!-- Author Section -->
              <div class="flex items-center justify-between p-4 bg-slate-700/50 rounded-xl">
                <div class="flex items-center gap-3">
                  <img
                    src={@recipe.user.profile_pic}
                    alt={@recipe.user.name}
                    class="w-12 h-12 rounded-full object-cover"
                  />
                  <div>
                    <a
                      href={"/profile/#{@recipe.user.id}"}
                      class="text-white font-semibold hover:text-primary-500 transition"
                    >
                      {@recipe.user.name}
                    </a>
                    <p class="text-slate-400 text-sm">{5} recipes</p>
                  </div>
                </div>
                <%= if !is_nil(@current_user) do %>
                  <button
                    phx-click="save_user_follow"
                    phx-value-follow_id={@recipe.user.id}
                    class={[
                      "px-4 py-2 rounded-lg font-medium transition",
                      (@recipe.user.id not in @user_follows &&
                         "bg-slate-600 text-white hover:bg-slate-500") ||
                        "bg-primary-500 text-white hover:bg-primary-600"
                    ]}
                  >
                    {if @recipe.user.id not in @user_follows, do: "Following", else: "Follow"}
                  </button>
                <% else %>
                  <a
                    href="/users/log_in"
                    class="px-4 py-2 rounded-lg font-medium transition bg-primary-500 text-white hover:bg-primary-600 rounded-full"
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
              ingredient_display_names={@ingredient_display_names}
            />
          </div>
          <%= if @interactions != [] do %>
            <div class="mt-20">
              <h2 class="text-lg font-semibold text-white mb-4">Nutrition Insights</h2>
              <.nutrient_interaction_panel interactions={@interactions} />
            </div>
          <% end %>

          <div
            class="mt-20 bg-slate-800 rounded-xl border border-slate-700 overflow-hidden"
            id="comments"
          >
            <button
              class="w-full flex justify-between items-center p-4 hover:bg-slate-700/30 transition relative"
              phx-click={JS.toggle_class("h-0 overflow-hidden mt-6", to: ".comment")}
            >
              <h3 class="text-white font-semibold">{"Comments (#{length(@recipe_comments)})"}</h3>

              <svg
                class={[
                  "w-5 h-5 text-slate-400 transition-transform"
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
              <%= if Enum.empty?(@recipe_comments) do %>
                <div class="text-center py-8 text-slate-500">
                  No comments yet. Be the first to comment!
                </div>
              <% else %>
                <div class="mt-2">
                  <%= for comment <- @recipe_comments do %>
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
    socket = assign(socket, :recipe_comments, recipe_comments)
    {:ok, socket}
  end

  @impl true
  def update(assigns, socket) do
    t0 = System.monotonic_time(:millisecond)

    user_follows =
      if(is_nil(Map.get(assigns, :user_follows))) do
        []
      else
        assigns.user_follows
      end

    comments = Food.get_recipe_comments(assigns.recipe.id)
    reply = Map.get(assigns, :reply, nil)
    interactions = Food.get_interactions_for_recipe(assigns.recipe)

    ingredient_ids =
      assigns.recipe.recipe_ingredients
      |> Enum.map(& &1.ingredient_id)

    display_names =
      Food.ingredient_display_names(ingredient_ids, assigns.recipe.language_name)

    server_ms = System.monotonic_time(:millisecond) - t0

    socket =
      socket
      |> assign(assigns)
      |> assign(:reply, reply)
      |> assign(:user_follows, user_follows)
      |> assign(:recipe_comments, comments)
      |> assign(:ingredient_display_names, display_names)
      |> assign(:interactions, interactions)
      |> assign(:server_ms, server_ms)
      |> assign(
        :comment,
        get_when_first_exists(assigns.current_user, fn ->
          %Comment{user_id: assigns.current_user.id, recipe_id: assigns.recipe.id}
        end)
      )

    {:ok, socket}
  end
end
