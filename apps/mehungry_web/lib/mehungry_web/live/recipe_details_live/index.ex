defmodule MehungryWeb.RecipeDetailsLive.Index do
  use MehungryWeb, :live_view
  use MehungryWeb.Searchable, :transfers_to_search

  import MehungryWeb.CoreComponents
  import MehungryWeb.RecipeComponents

  alias Mehungry.Posts.Comment
  alias Mehungry.Posts
  alias Mehungry.Food
  alias Mehungry.Food.RecipeUtils
  alias Mehungry.Accounts
  alias Mehungry.Food.Recipe

  embed_templates("components/*")

  def mount_search(_params, session, socket) do
    user =
      get_when_first_exists(session["user_token"], fn ->
        Accounts.get_user_by_session_token(session["user_token"])
      end)

    {
      :ok,
      socket
      |> assign(:user, user)
    }
  end

  @impl true
  def handle_params(params, uri, socket) do
    # maybe_track_user(nil, socket)
    socket = assign(socket, :path, uri)

    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, %{"id" => id, "origin" => origin}) do
    recipe = Food.get_recipe!(id)
    Posts.subscribe_to_post(%{recipe_id: recipe.id})
    {primaries_length, nutrients} = RecipeUtils.get_nutrients(recipe)

    comment =
      get_when_first_exists(socket.assigns.user, fn ->
        %Comment{user_id: socket.assigns.user.id, recipe_id: recipe.id}
      end)

    socket
    |> assign(:nutrients, nutrients)
    |> assign(:primary_size, primaries_length)
    |> assign(:recipe, recipe)
    |> assign(:page_title, recipe.title)
    |> assign(:comment, comment)
    |> assign(:reply, nil)
    |> assign(:return_to, origin)
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

  # cancel_comment_reply
  @impl true
  def handle_event("cancel_comment_reply", _, socket) do
    socket =
      socket
      |> assign(:reply, nil)

    {:noreply, socket}
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

  def get_color(treaty) do
    case treaty do
      true ->
        "#eb4034"

      false ->
        "none"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.recipe_modal
      :if={@live_action in [:index]}
      on_cancel={JS.patch(~p"/#{@return_to}")}
      id="recipe_details_modal"
      show
    >
      <div id="recipe_presentation_modal" class="sm:p-6">
        <div class="basic_2_col_grid_cont">
          <div class="w-full">
            <img class="min-h-96 rounded-2xl w-full" src={@recipe.image_url} />
          </div>
          <div class="w-full">
            <.user_overview_card user={@recipe.user} . />
            <h3 class="m-2 mt-4  text-center w-full"><%= @recipe.title %></h3>
            <div style="">
              <.recipe_details recipe={@recipe} nutrients={@nutrients} primary_size={@primary_size} . />
            </div>
            <div class="post_card w-11/12 mb-12">
              <div class="grid grid-cols-2 h-fit mt-16">
                <h3 class="text-lg text-start ">Comments</h3>
                <div
                  class="relative"
                  phx-click={JS.toggle_class("h-0 overflow-hidden mt-4", to: ".comment")}
                >
                  <.icon
                    name="hero-arrow-down"
                    style="color: rgb(75 85 99);"
                    class="mt-0.5 h-5 w-5 flex-none font-bold cursor-pointer text-end absolute right-2"
                  />
                </div>
              </div>
              <div style="max-height: 300px; overflow: auto;">
                <%= for comment <- @recipe.comments do %>
                  <.comment
                    comment={comment}
                    user={comment.user}
                    current_user={@user}
                    live_action={@live_action}
                    page_title={@page_title}
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
    </.recipe_modal>
    """
  end

  def handle_info(%{new_comment: comment}, socket) do
    recipe = socket.assigns.recipe
    comment = Posts.get_comment!(comment.id)

    comments =
      Enum.into(Enum.filter(recipe.comments, fn x -> x.id != comment.id end), [comment])
      |> Enum.sort_by(& &1.updated_at)

    recipe = %Recipe{
      recipe
      | comments: comments
    }

    socket =
      socket
      |> assign(:recipe, recipe)

    {:noreply, socket}
  end

  @impl true
  def update(assigns, socket) do
    socket =
      assign(socket, assigns)
      |> assign(:reply, nil)
      |> assign(
        :comment,
        get_when_first_exists(socket.assigns.user, fn ->
          %Comment{user_id: socket.assigns.user.id, recipe_id: socket.assigns.recipe.id}
        end)
      )

    {:ok, socket}
  end
end
