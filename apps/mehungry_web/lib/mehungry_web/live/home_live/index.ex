defmodule MehungryWeb.HomeLive.Index do
  use MehungryWeb, :live_view
  use MehungryWeb.Presence, :user_tracking

  import MehungryWeb.RecipeComponents

  use MehungryWeb.LiveHelpers, :hook_for_update_recipe_details_component

  embed_templates("components/*")
  @per_page 10

  alias Mehungry.Accounts
  alias Mehungry.Posts
  alias Mehungry.Users
  alias Mehungry.Food

  @impl true
  def mount(_params, session, socket) do
    user =
      case is_nil(session["user_token"]) do
        true ->
          nil

        false ->
          Accounts.get_user_by_session_token(session["user_token"])
      end

    all_posts =
      Mehungry.Posts.list_posts(user)
      |> Enum.filter(fn x -> !is_nil(x) and !is_nil(x.reference) end)

    {user_profile, user_follows, user_recipes} = Accounts.get_user_essentials(user)
    current_user_follows = Enum.map(user_follows, fn x -> x.follow_id end)

    Enum.each(all_posts, fn post ->
      Posts.subscribe_to_post(%{post_id: post.id})
    end)

    {:ok,
     socket
     |> assign(:user, user)
     |> assign(:all_posts, all_posts)
     |> assign(:posts, Enum.take(all_posts, @per_page))
     |> assign(:page, 1)
     |> assign(:posts_exhausted, length(all_posts) <= @per_page)
     |> assign(:user_profile, user_profile)
     |> assign(:current_user_follows, current_user_follows)
     |> assign(:current_user_recipes, user_recipes)
     |> assign(:must_be_loged_in, nil)
     |> assign(:page_title, "Browse Recipes")}
  end

  @impl true
  def handle_event("load-more", _params, socket) do
    %{all_posts: all_posts, page: page} = socket.assigns
    next_page = page + 1
    displayed = Enum.take(all_posts, next_page * @per_page)

    {:noreply,
     socket
     |> assign(:posts, displayed)
     |> assign(:page, next_page)
     |> assign(:posts_exhausted, length(displayed) >= length(all_posts))}
  end

  @impl true
  def handle_event("keep_browsing", _thing, socket) do
    {:noreply, assign(socket, :must_be_loged_in, nil)}
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

  defp get_recipe_description(assigns) do
    terms = String.split(assigns.description || "", " ")

    {_hashtags, other} =
      Enum.split_with(terms, fn x -> String.starts_with?(x, "#") end)

    text = Enum.join(other, " ")
    truncated = if String.length(text) > 150, do: String.slice(text, 0, 150) <> "…", else: text

    assigns = Map.put(assigns, :description, truncated)

    ~H"""
    <span class="flex gap-2 flex-wrap">
      <div class="w-full break-words">{@description}</div>
      <%= for tag <- @recipe.recipe_hashtags do %>
        <.recipe_tag hashtag={tag.hashtag} />
      <% end %>
    </span>
    """
  end

  defp apply_action(socket, :index, _params) do
    maybe_track_user(%{}, socket)

    socket
  end

  defp apply_action(socket, :share_social_media, %{"id" => id, "social_media" => social_media}) do
    maybe_track_user(%{}, socket)

    recipe = Food.get_recipe!(id)
    Posts.subscribe_to_recipe(%{recipe_id: recipe.id})

    socket
    |> assign(:recipe, recipe)
    |> assign(:social_media, social_media)
  end

  defp apply_action(socket, :show_recipe, %{"id" => id}) do
    maybe_track_user(%{}, socket)

    recipe = Food.get_recipe!(id |> String.split("#") |> List.first() |> String.to_integer())

    if !is_nil(recipe) do
      Posts.subscribe_to_recipe(%{recipe_id: recipe.id})

      user = socket.assigns.user

      user_recipes =
        case is_nil(user) do
          true ->
            []

          false ->
            Users.list_user_saved_recipe_ids(user)
        end

      socket
      |> assign(:page_title, recipe.title)
      |> assign(:page_seo_data, %{
        title: recipe.title,
        img: recipe.image_url,
        id: Integer.to_string(recipe.id)
      })
      |> assign(:recipe, recipe)
      |> assign(:current_user_recipes, user_recipes)
    else
      socket |> put_flash(:error, "Recipe not found") |> push_navigate(to: "/home")
    end
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
        {MehungryWeb.SocialMediaPostComponent, %{post_result: results} = _parameters},
        socket
      ) do
    results =
      Enum.map(results, fn {name, status, body} ->
        {:ok, body} = Jason.decode(body)
        {name, status, body["error"]["message"]}
      end)

    send_update(MehungryWeb.SocialMediaPostComponent, %{
      state: :result,
      results: results,
      id: "recipe_social_media_component"
    })

    {:noreply, socket}
  end

  @impl true
  def handle_info({MehungryWeb.SocialMediaPostComponent, :close}, socket) do
    {:noreply, push_patch(socket, to: ~p"/home")}
  end

  @impl true
  def handle_info(%{new_vote: vote, type_: _type_}, socket) do
    post = Posts.get_post!(vote.post_id)

    update_post = fn list ->
      Enum.map(list, fn x -> if x.id == post.id, do: post, else: x end)
    end

    {:noreply,
     socket
     |> assign(:all_posts, update_post.(socket.assigns.all_posts))
     |> assign(:posts, update_post.(socket.assigns.posts))}
  end
end
