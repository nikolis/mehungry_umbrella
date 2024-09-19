defmodule MehungryWeb.RecipeDetailsComponent do
  use MehungryWeb, :live_component

  import MehungryWeb.CoreComponents
  import MehungryWeb.RecipeComponents

  alias Mehungry.Posts.Comment
  alias Mehungry.{Posts, Users}
  alias Mehungry.Food.Recipe

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
  def handle_event("save_user_recipe", %{"recipe_id" => recipe_id, "dom_id" => _dom_id}, socket) do
    case is_nil(socket.assigns.user) do
      true ->
        socket = assign(socket, :must_be_loged_in, 1)
        {:noreply, socket}

      false ->
        {recipe_id, _ignore} = Integer.parse(recipe_id)
        toggle_user_saved_recipes(socket, recipe_id)

        Users.list_user_saved_recipes(socket.assigns.user)
        |> Enum.map(fn x -> x.recipe_id end)

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
    <div id="recipe_presentation_modal" class="sm:p-6">
      <div class="basic_2_col_grid_cont">
        <div class="w-full">
          <.recipe_like_container
            type="browse"
            user_recipes={@user_recipes}
            recipe={@recipe}
            id={@id}
            myself={@myself}
          />
          <img class="min-h-96 rounded-2xl w-full" src={@recipe.image_url} />
          <h3 class="m-2 mt-4  text-center w-full"><%= @recipe.title %></h3>
          <.recipe_attrs_container recipe={@recipe} />
        </div>
        <div class="w-full">
          <.user_overview_card user={@recipe.user} user_follows={@user_follows} />
          <div class="mt-8">
            <.recipe_details recipe={@recipe} nutrients={@nutrients} primary_size={@primary_size} . />
          </div>
          <div class="post_card w-11/12 mb-12">
            <div class="grid grid-cols-2 h-fit mt-16">
              <h3 class="text-lg text-start "><%= "Comments (#{length(@recipe.comments)})" %></h3>
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
              <%= for comment <- @recipe.comments do %>
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

  def handle_info(%{new_comment: comment}, socket) do
    IO.inspect("New comment inside recipe detals live")

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
    IO.inspect(assigns.recipe, label: "Recipe from recipe detauls index")

    socket =
      assign(socket, assigns)
      |> assign(:reply, nil)
      |> assign(assigns)
      |> assign(:recipe, assigns.recipe)
      |> assign(
        :comment,
        get_when_first_exists(assigns.user, fn ->
          %Comment{user_id: assigns.user.id, recipe_id: assigns.recipe.id}
        end)
      )

    {:ok, socket}
  end
end
