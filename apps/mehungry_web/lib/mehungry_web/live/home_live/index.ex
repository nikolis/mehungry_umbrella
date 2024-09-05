defmodule MehungryWeb.HomeLive.Index do
  use MehungryWeb, :live_view
  use MehungryWeb.Searchable, :transfers_to_search

  embed_templates("components/*")
  @color_fill "#00A0D0"

  alias Mehungry.Inventory
  alias Mehungry.Accounts
  alias Mehungry.Posts
  alias Mehungry.Users
  alias Mehungry.Food
  alias Mehungry.Food.RecipeUtils

  def mount_search(_params, session, socket) do
    user =
      case is_nil(session["user_token"]) do
        true ->
          nil

        false ->
          Accounts.get_user_by_session_token(session["user_token"])
      end

    user_profile =
      case is_nil(user) do
        true ->
          nil

        false ->
          Accounts.get_user_profile_by_user_id(user.id)
      end

    posts = Mehungry.Posts.list_posts(user)

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

    Enum.each(posts, fn post ->
      Posts.subscribe_to_post(%{post_id: post.id})
    end)

    {:ok,
     socket
     |> assign(:user, user)
     |> assign(:posts, posts)
     |> assign(:user_posts, user_posts)
     |> assign(:user_profile, user_profile)
     |> assign(:user_follows, user_follows)
     |> assign(:must_be_loged_in, nil)}
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
        # socket = stream_delete(socket, :recipes, recipe)
        # socket = stream_insert(socket, :recipes, recipe)
        socket = assign(socket, :user_recipes, user_recipes)
        {:noreply, socket}
    end
  end

  def handle_event("navigate_to_post_details", %{"id" => post_id}, socket) do
    {:noreply, push_navigate(socket, to: "/post/" <> to_string(post_id))}
  end

  def handle_event("delete_basket", %{"id" => basket_id}, socket) do
    bs = Inventory.get_shopping_basket!(basket_id)
    Inventory.delete_shopping_basket(bs)

    {:noreply,
     socket
     |> assign(:shopping_basket, nil)}
  end

  def handle_event("react", %{"type_" => type, "id" => post_id}, socket) do
    case is_nil(socket.assigns.user) do
      true ->
        {:noreply, assign(socket, :must_be_loged_in, 1)}

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

  defp apply_action(socket, :index, _params) do
    socket
  end

  defp apply_action(socket, :show_recipe, %{"id" => id}) do
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
  end

  defp get_nutrient_category(nutrients, category_name, category_sum_name) do
    {category, rest} =
      Enum.split_with(nutrients, fn x -> String.contains?(x.name, category_name) end)

    case length(category) > 0 do
      true ->
        {category_total, rest} =
          Enum.split_with(rest, fn x ->
            String.contains?(x.name, category_sum_name)
          end)

        case length(category_total) == 1 do
          true ->
            {Enum.into(Enum.at(category_total, 0), children: category), rest}

          false ->
            {%{
               amount: 111.1,
               measurement_unit: "to be defined",
               children: category,
               name: category_sum_name
             }, rest}
        end

      false ->
        {nil, rest}
    end
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
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
