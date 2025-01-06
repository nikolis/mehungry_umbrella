defmodule MehungryWeb.HomeLive.Index do
  use MehungryWeb, :live_view
  use MehungryWeb.Searchable, :transfers_to_search
  use MehungryWeb.Presence, :user_tracking

  import MehungryWeb.RecipeComponents

  # use MehungryWeb.LiveHelpers, :hook_for_update_recipe_details_component
  embed_templates("components/*")
  @color_fill "#00A0D0"

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

    posts = Mehungry.Posts.list_posts(user)

    posts = Enum.filter(posts, fn x -> !is_nil(x) end)
    {user_profile, user_follows, user_recipes} = Accounts.get_user_essentials(user)

    Enum.each(posts, fn post ->
      Posts.subscribe_to_post(%{post_id: post.id})
    end)

    IO.inspect("HOme live")

    {:ok,
     socket
     |> assign(:user, user)
     |> assign(:posts, posts)
     |> assign(:user_profile, user_profile)
     |> assign(:user_follows, user_follows)
     |> assign(:current_user_recipes, user_recipes)
     |> assign(:search_changeset, nil)
     |> assign(:query_string, "")
     |> assign(:must_be_loged_in, nil)
     |> assign(:page_title, "Browse Recipes")}
  end

  @impl true
  def handle_event("keep_browsing", _thing, socket) do
    {:noreply, assign(socket, :must_be_loged_in, nil)}
  end

  defp get_recipe_description(assigns) do
    terms = String.split(assigns.description, " ")

    {hashtags, other} =
      Enum.split_with(terms, fn x ->
        case String.at(x, 0) == "#" do
          true ->
            true

          false ->
            false
        end
      end)

    Enum.map(hashtags, fn x ->
      %{hashtag: %{title: x}}
    end)

    assigns = Map.put(assigns, :description, other)

    ~H"""
    <span class=" flex gap-2  flex-wrap">
      <div class="w-full break-words	"><%= @description %></div>
      <%= for tag <- @recipe.recipe_hashtags do %>
        <.recipe_tag hashtag={tag.hashtag} />
      <% end %>
    </span>
    """
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

  defp apply_action(socket, :index, _params) do
    maybe_track_user(%{}, socket)

    socket
  end

  defp apply_action(socket, :share_social_media, %{"id" => id}) do
    maybe_track_user(%{}, socket)

    recipe = Food.get_recipe!(id)
    Posts.subscribe_to_recipe(%{recipe_id: recipe.id})

    socket
    |> assign(:recipe, recipe)
  end

  defp apply_action(socket, :show_recipe, %{"id" => id}) do
    maybe_track_user(%{}, socket)

    recipe = Food.get_recipe!(id)
    Posts.subscribe_to_recipe(%{recipe_id: recipe.id})

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
    |> assign(:page_title, %{
      title: recipe.title <> "Browse Recipes",
      img: recipe.image_url,
      id: Integer.to_string(recipe.id)
    })
    |> assign(:primary_size, primaries_length)
    |> assign(:recipe, recipe)
    |> assign(:current_user_recipes, user_recipes)
  end

  @impl true
  def handle_params(params, uri, socket) do
    socket = assign(socket, :path, uri)
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
  def handle_info(
        {MehungryWeb.SocialMediaPostComponent, %{post_result: results} = parameters},
        socket
      ) do
    results =
      Enum.map(results, fn {name, status, body} ->
        {:ok, body} = Jason.decode(body)
        {name, status, body["error"]["message"]}
      end)

    IO.inspect(results, label: "Result")

    send_update(MehungryWeb.SocialMediaPostComponent, %{
      state: :result,
      results: results,
      id: "recipe_social_media_component"
    })

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

  """
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
  """
end
