defmodule MehungryWeb.HomeLive.Show do
  use MehungryWeb, :live_view

  embed_templates("components/*")

  alias Mehungry.Accounts
  alias Mehungry.Posts.Comment
  alias Mehungry.Posts.Post
  alias Mehungry.Posts
  alias Mehungry.Users

  @color_fill "#00A0D0"

  @impl true
  def mount(%{"id" => id} = _params, session, socket) do
    user = Accounts.get_user_by_session_token(session["user_token"])
    post = Posts.get_post!(id)
    Posts.subscribe_to_post(%{post_id: id})

    user_posts = Users.list_user_saved_posts(user)
    user_posts = Enum.map(user_posts, fn x -> x.post_id end)

    user_follows = Users.list_user_follows(user)
    user_follows = Enum.map(user_follows, fn x -> x.follow_id end)

    {:ok,
     socket
     |> assign(:comment, %Comment{user_id: user.id, post_id: id})
     |> assign(:user, user)
     |> assign(:post, post)
     |> assign(:user_posts, user_posts)
     |> assign(:user_follows, user_follows)
     |> assign(:reply, nil)}
  end

  def get_style(item_list, user_id, get_attr) do
    has = Enum.any?(item_list, fn x -> get_attr.(x) == user_id end)

    case has do
      true ->
        @color_fill

      false ->
        "#FFFFFF"
    end
  end

  def get_style2(item_list, user_id, positive) do
    has = Enum.any?(item_list, fn x -> x.user_id == user_id and x.positive == positive end)

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
  def handle_event("vote_comment", %{"id" => comment_id, "reaction" => reaction}, socket) do
    Mehungry.Posts.vote_comment(comment_id, socket.assigns.user.id, reaction)

    {:noreply, socket}
  end

  def handle_event("add-reply-form", %{"id" => comment_id}, socket) do
    {comment_id, _} = Integer.parse(comment_id)

    socket =
      socket
      |> assign(:reply, %{comment_id: comment_id})

    {:noreply, socket}
  end

  @impl true
  def handle_event("save_post", %{"post_id" => post_id}, socket) do
    {post_id, _ignore} = Integer.parse(post_id)
    toggle_user_saved_posts(socket, post_id)
    user_posts = Users.list_user_saved_posts(socket.assigns.user)
    user_posts = Enum.map(user_posts, fn x -> x.post_id end)
    socket = assign(socket, :user_posts, user_posts)
    {:noreply, socket}
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

  def handle_event("cancel_comment_reply", _, socket) do
    socket =
      socket
      |> assign(:reply, nil)

    {:noreply, socket}
  end

  def handle_event("react", %{"type_" => type, "id" => post_id}, socket) do
    case type do
      "upvote" ->
        Posts.upvote_post(post_id, socket.assigns.user.id)

      "downvote" ->
        Posts.downvote_post(post_id, socket.assigns.user.id)
    end

    {:noreply, socket}
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
  def handle_params(%{"id" => _id}, _, socket) do
    {:noreply,
     socket
     |> assign(:page_title, page_title(socket.assigns.live_action))}
  end

  def toggle_user_saved_posts(socket, post_id) do
    case Enum.any?(socket.assigns.user_posts, fn x -> x == post_id end) do
      true ->
        Users.remove_user_saved_post(socket.assigns.user.id, post_id)

      false ->
        Users.save_user_post(socket.assigns.user.id, post_id)
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

  defp page_title(:show), do: "Show Post"
  defp page_title(:edit), do: "Edit User profile"
end
