defmodule MehungryWeb.RecipeDetailsComponent do
  use MehungryWeb, :live_component

  import MehungryWeb.CoreComponents
  import MehungryWeb.RecipeComponents

  alias Mehungry.Posts.Comment
  alias Mehungry.{Posts, Users, Food, Accounts}
  alias Mehungry.Api.Instagram

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
          Users.list_user_saved_recipes(socket.assigns.user)
          |> Enum.map(fn x -> x.recipe_id end)

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
    <div id="recipe_presentation_modal" class="">
      <div class="basic_2_col_grid_cont">
        <div class="w-full">
          <.recipe_like_container
            type="browse"
            user_recipes={@user_recipes}
            recipe={@recipe}
            id={@id <> "like_container"}
            myself={@myself}
          />
          <img style="max-height: 215px;" class="min-h-96 rounded-2xl w-full" src={@recipe.image_url} />
          <h3 class="m-2  max-h-16 overflow-hidden text-center text-xl w-full">
            <%= @recipe.title %>
          </h3>
          <.recipe_attrs_container recipe={@recipe} />
        </div>
        <div class="w-full mt-2">
          <%= if @recipe.user_id == @user.id do %>
            <button
              class="px-4 rounded-md py-1"
              phx-target={@myself}
              phx-click="post-on-instagram"
              phx-value-recipe_id={@recipe.id}
              phx-value-user_id={@user.id}
            >
              Instagram Post
            </button>
          <% else %>
            <.user_overview_card user={@recipe.user} user_follows={@user_follows} />
          <% end %>
          <div class="mt-8">
            <.recipe_details recipe={@recipe} nutrients={@nutrients} primary_size={@primary_size} . />
          </div>
          <div class="post_card w-11/12 mb-12">
            <div class="grid grid-cols-2 h-fit mt-16">
              <h3 class="text-lg text-start "><%= "Comments (#{length(@recipe_comments)})" %></h3>
              <div
                class="relative"
                phx-click={JS.toggle_class("h-0 overflow-hidden mt-4", to: ".comment")}
              >
                <.icon
                  name="hero-arrow-down"
                  class="mt-0.5 h-5 w-5 flex-none font-bold cursor-pointer text-end absolute right-2"
                />
              </div>
            </div>
            <div style="max-height: 300px; overflow: auto;">
              <%= for comment <- @recipe_comments do %>
                <.comment
                  comment={comment}
                  user={comment.user}
                  current_user={@user}
                  live_action={@live_action}
                  page_title={@page_title}
                  myself={@myself}
                  reply={@reply}
                />
              <% end %>
            </div>
          </div>

          <%= if !is_nil(@user) do %>
            <.live_component
              module={MehungryWeb.RecipeDetailsLive.FormComponentComment}
              id="comment_form"
              title={@page_title}
              action={@live_action}
              current_user={@user}
              comment={@comment}
            />
          <% end %>
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
    user_follows =
      if(is_nil(Map.get(assigns, :user_follows))) do
        nil
      else
        assigns.user_follows
      end

    comments = Food.get_recipe_comments(assigns.recipe.id)
    reply = Map.get(assigns, :reply, nil)

    socket =
      socket
      |> assign(assigns)
      |> assign(:reply, reply)
      |> assign(:user_follows, user_follows)
      |> assign(:recipe_comments, comments)
      |> assign(
        :comment,
        get_when_first_exists(assigns.user, fn ->
          %Comment{user_id: assigns.user.id, recipe_id: assigns.recipe.id}
        end)
      )

    {:ok, socket}
  end
end
