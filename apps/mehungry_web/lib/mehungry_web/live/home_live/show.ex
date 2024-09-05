defmodule MehungryWeb.HomeLive.Show do
  use MehungryWeb, :live_view
  use MehungryWeb.Searchable, :transfers_to_search

  embed_templates("components/*")

  alias Mehungry.Accounts
  alias Mehungry.Posts.Comment
  alias Mehungry.Posts.Post
  alias Mehungry.Posts
  alias Mehungry.Users
  alias Mehungry.Food
  alias Mehungry.Food.RecipeUtils

  @color_fill "#00A0D0"

  def mount_search(%{"id" => id} = _params, session, socket) do
    user =
      case is_nil(session["user_token"]) do
        true ->
          nil

        false ->
          Accounts.get_user_by_session_token(session["user_token"])
      end

    post = Posts.get_post!(id)
    Posts.subscribe_to_post(%{post_id: id})

    {user_posts, user_follows} =
      case is_nil(user) do
        true ->
          {nil, nil}

        false ->
          user_posts = Users.list_user_saved_posts(user)
          user_posts = Enum.map(user_posts, fn x -> x.post_id end)
          user_follows = Users.list_user_follows(user)
          user_follows = Enum.map(user_follows, fn x -> x.follow_id end)
          {user_posts, user_follows}
      end

    {:ok,
     socket
     |> assign(
       :comment,
       case user do
         nil ->
           nil

         user ->
           %Comment{user_id: user.id, post_id: id}
       end
     )
     |> assign(:user, user)
     |> assign(:post, post)
     |> assign(:user_posts, user_posts)
     |> assign(:must_be_loged_in, nil)
     |> assign(:user_follows, user_follows)
     |> assign(:reply, nil)}
  end

  def get_style(item_list, user, get_attr) do
    has =
      case is_nil(user) or is_nil(item_list) or Enum.empty?(item_list) do
        true ->
          false

        false ->
          Enum.any?(item_list, fn x -> get_attr.(x) == user.id end)
      end

    case has do
      true ->
        @color_fill

      false ->
        "#FFFFFF"
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
        {:noreply, assign(socket, :must_be_loged_in, 1)}

      false ->
        {recipe_id, _ignore} = Integer.parse(recipe_id)
        toggle_user_saved_recipes(socket, recipe_id)
        user_recipes = Users.list_user_saved_recipes(socket.assigns.user)
        user_recipes = Enum.map(user_recipes, fn x -> x.recipe_id end)

        {:noreply,
         push_patch(assign(socket, :user_recipes, user_recipes),
           to: ~p"/post/#{socket.assigns.post.id}/show_recipe/#{socket.assigns.recipe.id}"
         )}
    end
  end

  @impl true
  def handle_event("vote_comment", %{"id" => comment_id, "reaction" => reaction}, socket) do
    case is_nil(socket.assigns.user) do
      true ->
        {:noreply, assign(socket, :must_be_loged_in, 1)}

      false ->
        Mehungry.Posts.vote_comment(comment_id, socket.assigns.user.id, reaction)
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
  def handle_event("save_post", %{"post_id" => post_id}, socket) do
    case is_nil(socket.assigns.user) do
      true ->
        socket = assign(socket, :must_be_loged_in, 1)
        {:noreply, socket}

      false ->
        {post_id, _ignore} = Integer.parse(post_id)
        toggle_user_saved_posts(socket, post_id)
        user_posts = Users.list_user_saved_posts(socket.assigns.user)
        user_posts = Enum.map(user_posts, fn x -> x.post_id end)
        socket = assign(socket, :user_posts, user_posts)
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("save_user_follow", %{"follow_id" => follow_id}, socket) do
    {follow_id, _ignore} = Integer.parse(follow_id)
    toggle_user_follow(socket, follow_id)
    user_follows = Users.list_user_follows(socket.assigns.user)
    user_follows = Enum.map(user_follows, fn x -> x.follow_id end)
    socket = assign(socket, :user_follows, user_follows)
    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel_comment_reply", _, socket) do
    socket =
      socket
      |> assign(:reply, nil)

    {:noreply, socket}
  end

  @impl true
  def handle_event("react", %{"type_" => type, "id" => post_id}, socket) do
    case is_nil(socket.assigns.user) do
      true ->
        socket = assign(socket, :must_be_loged_in, 1)
        {:noreply, socket}

      false ->
        case type do
          "upvote" ->
            Posts.upvote_post(post_id, socket.assigns.user.id)

          "downvote" ->
            Posts.downvote_post(post_id, socket.assigns.user.id)
        end

        {:noreply, socket}
    end
  end

  @impl true
  def handle_info(%{new_vote: _vote, type_: _type_}, socket) do
    post = socket.assigns.post
    post = Posts.get_post!(post.id)

    socket =
      socket
      |> assign(:post, post)

    {:noreply, socket}
  end

  def handle_info(%{new_comment: comment}, socket) do
    post = socket.assigns.post
    comment = Posts.get_comment!(comment.id)

    post = %Post{
      post
      | comments: Enum.into(Enum.filter(post.comments, fn x -> x.id != comment.id end), [comment])
    }

    socket =
      socket
      |> assign(:post, post)

    {:noreply, socket}
  end

  def handle_info({MehungryWeb.HomeLive.FormComponentComment, {:saved, _comment}}, socket) do
    post = socket.assigns.post

    socket =
      socket
      |> assign(:post, post)
      |> put_flash(:info, "Comment has been sent")

    {:noreply, socket}
  end

  def handle_info({MehungryWeb.HomeLive.FormComponentCommentAnswer, {:saved, _comment}}, socket) do
    post = socket.assigns.post

    socket =
      socket
      |> assign(:post, post)
      |> assign(:reply, nil)
      |> put_flash(:info, "Comment has been sent")

    {:noreply, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :show, %{"id" => _post_id}) do
    socket
    |> assign(:page_title, page_title(socket.assigns.live_action))
  end

  defp apply_action(socket, :show_recipe, %{"id" => id, "rec_id" => _rec_id}) do
    recipe = Food.get_recipe!(id)

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
    |> assign(:page_title, page_title(socket.assigns.live_action))
  end

  def toggle_user_saved_posts(socket, post_id) do
    case is_nil(socket.assigns.user) do
      true ->
        socket = assign(socket, :must_be_loged_in, 1)
        {:noreply, socket}

      false ->
        case Enum.any?(socket.assigns.user_posts, fn x -> x == post_id end) do
          true ->
            Users.remove_user_saved_post(socket.assigns.user.id, post_id)

          false ->
            Users.save_user_post(socket.assigns.user.id, post_id)
        end
    end
  end

  def toggle_user_follow(socket, follow_id) do
    case Enum.any?(socket.assigns.user_follows, fn x -> x == follow_id end) do
      true ->
        Users.remove_user_follow(socket.assigns.user.id, follow_id)

      false ->
        Users.save_user_follow(socket.assigns.user.id, follow_id)
    end
  end

  defp page_title(:show_recipe), do: "Show Recipe"
  defp page_title(:show), do: "Show Post"
  defp page_title(:edit), do: "Edit User profile"
end
