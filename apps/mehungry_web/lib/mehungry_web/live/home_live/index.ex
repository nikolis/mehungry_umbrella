defmodule MehungryWeb.HomeLive.Index do
  use MehungryWeb, :live_view
  use MehungryWeb.Searchable, :transfers_to_search

  embed_templates("components/*")
  @color_fill "#00A0D0"


  alias Mehungry.Inventory
  alias Mehungry.Accounts
  alias Mehungry.Posts

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

  @impl true
  def mount(_params, session, socket) do
    user = Accounts.get_user_by_session_token(session["user_token"])
    posts = Mehungry.Posts.list_posts()

    Enum.each(posts, fn post ->
      Posts.subscribe_to_post(%{post_id: post.id})
    end)

    {:ok,
     socket
     |> assign(:user, user)
     |> assign(:posts, Mehungry.Posts.list_posts())}
  end

  defp apply_action(socket, :index, _params) do
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
    IO.inspect(type, label: "THe vodte: ")

    case type do
      "upvote" ->
        Posts.upvote_post(post_id, socket.assigns.user.id)

      "downvote" ->
        Posts.downvote_post(post_id, socket.assigns.user.id)
    end

    {:noreply, socket}
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

  def get_style(item_list, user_id) do
    has = Enum.any?(item_list, fn x -> x.user_id == user_id end)

    case has do
      true ->
        @color_fill

      false ->
        "#FFFFFF"
    end
  end

end
