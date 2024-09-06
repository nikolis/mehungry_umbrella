defmodule MehungryWeb.RecipeBrowserLive.RecipeDetailsComponent do
  use MehungryWeb, :live_component
  import MehungryWeb.CoreComponents
  alias Mehungry.Posts.Comment

  embed_templates("components/*")

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
    <div id="recipe_presentation_modal" class="p-6">
      <div class="grid grid-cols-2 gap-6">
        <div class="w-full">
          <img class="min-h-96 rounded-2xl" src={@recipe.image_url} />
        </div>
        <div class="w-full">
          <.user_overview_card user={@recipe.user} . />
          <h3 class="m-2 mt-4  text-center w-full"><%= @recipe.title %></h3>
          <div style="">
            <.recipe_details recipe={@recipe} nutrients={@nutrients} primary_size={@primary_size} . />
          </div>
          <div class="mt-20"></div>
          <%= if !is_nil(@user) do %>
            <.live_component
              module={MehungryWeb.HomeLive.FormComponentComment}
              id="comment_form"
              title={@page_title}
              action={@live_action}
              current_user={@user}
              comment={@comment}
            />
          <% end %>
        </div>
        <!--         <div class="post_card mb-12">
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
          </div> -->
      </div>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    socket =
      assign(socket, assigns)
      |> assign(:reply, nil)
      |> assign(
        :comment,
        case assigns.user do
          nil ->
            nil

          user ->
            %Comment{user_id: user.id, recipe_id: assigns.recipe.id}
        end
      )

    {:ok, socket}
  end
end
