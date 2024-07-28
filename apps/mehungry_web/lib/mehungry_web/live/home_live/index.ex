defmodule MehungryWeb.HomeLive.Index do
  use MehungryWeb, :live_view
  use MehungryWeb.Searchable, :transfers_to_search

  embed_templates("components/*")
  @color_fill "#00A0D0"

  alias Mehungry.Inventory
  alias Mehungry.Accounts
  alias Mehungry.Posts
  alias Mehungry.Users
  alias Mehungry.Accounts.UserPost
  alias Mehungry.Accounts.UserFollow

  @impl true
  def mount(params, session, socket) do
    user = Accounts.get_user_by_session_token(session["user_token"])
    user_profile = Accounts.get_user_profile_by_user_id(user.id)
    posts = Mehungry.Posts.list_posts(user)

    user_posts = Users.list_user_saved_posts(user)
    user_posts = Enum.map(user_posts, fn x -> x.post_id end)

    user_follows = Users.list_user_follows(user)
    user_follows = Enum.map(user_follows, fn x -> x.follow_id end)

    Enum.each(posts, fn post ->
      Posts.subscribe_to_post(%{post_id: post.id})
    end)

    {:ok,
     socket
     |> assign(:user, user)
     |> assign(:posts, posts)
     |> assign(:user_posts, user_posts)
     |> assign(:user_profile, user_profile)
     |> assign(:user_follows, user_follows)}
  end

  defp apply_action(socket, :index, params) do
    socket
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  def handle_event("navigate_to_post_details", %{"id" => post_id}, socket) do
    {:noreply, push_redirect(socket, to: "/post/" <> to_string(post_id))}
  end

  def handle_event("delete_basket", %{"id" => basket_id}, socket) do
    bs = Inventory.get_shopping_basket!(basket_id)
    Inventory.delete_shopping_basket(bs)

    {:noreply,
     socket
     |> assign(:shopping_basket, nil)}
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
  def handle_info({MehungryWeb.Onboarding.FormComponent, "profile-saved"}, socket) do
    user_profile = Accounts.get_user_profile_by_user_id(socket.assigns.user.id)

    {:noreply,
     socket
     |> assign(:user_profile, user_profile)}
  end

  @impl true
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

  def get_style(item_list, user_id, get_attr) do
    has = Enum.any?(item_list, fn x -> get_attr.(x) == user_id end)

    case has do
      true ->
        @color_fill

      false ->
        "#FFFFFF"
    end
  end

  def get_style(item_list, user_id) do
    has = Enum.any?(item_list, fn x -> x.user_id == user_id end)

    case has do
      true ->
        @color_fill

      false ->
        "#FFFFFF"
    end
  end

  def get_positive_votes(votes) do
    Enum.reduce(votes, 0, fn x, acc ->
      if x.positive do
        acc + 1
      end
    end)
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
end
