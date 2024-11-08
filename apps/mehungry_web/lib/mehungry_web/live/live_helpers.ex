defmodule MehungryWeb.LiveHelpers do
  @moduledoc false

  import Phoenix.Component

  alias Phoenix.LiveView.JS
  alias Mehungry.Food.Recipe
  alias Mehungry.Users
  alias Mehungry.Food

  def hook_for_update_recipe_details_component do
    quote do
      def toggle_user_saved_recipe(socket, recipe_id) do
        case is_nil(socket.assigns.current_user) do
          true ->
            assign(socket, :must_be_loged_in, 1)

          false ->
            case Enum.any?(socket.assigns.current_user_recipes, fn x -> x == recipe_id end) do
              true ->
                Users.remove_user_saved_recipe(socket.assigns.current_user.id, recipe_id)

              false ->
                Users.save_user_recipe(socket.assigns.current_user.id, recipe_id)
            end
        end
      end

      def toggle_user_follow(socket, follow_id) do
        case Enum.any?(socket.assigns.user_follows, fn x -> x == follow_id end) do
          true ->
            Users.remove_user_follow(socket.assigns.current_user.id, follow_id)

          false ->
            Users.save_user_follow(socket.assigns.current_user.id, follow_id)
        end
      end

      @impl true
      def handle_info(%{new_comment_vote: vote, type_: _type_}, socket) do
        recipe_comments = Food.get_recipe_comments(vote.recipe_id)
        assigns = Map.put(%{}, :recipe_comments, recipe_comments)
        assigns = Map.put(assigns, :id, "recipe_details_component")

        send_update(MehungryWeb.RecipeDetailsComponent, assigns)

        {:noreply, socket}
      end

      @impl true
      def handle_event("cancel_comment_reply", _, socket) do
        assigns = Map.put(%{}, :reply, nil)
        assigns = Map.put(assigns, :id, "recipe_details_component")
        send_update(MehungryWeb.RecipeDetailsComponent, assigns)

        {:noreply, assign(socket, :reply, nil)}
      end

      @impl true
      def handle_event("save_user_recipe", %{"recipe_id" => recipe_id}, socket) do
        {recipe_id, _ignore} = Integer.parse(recipe_id)
        toggle_user_saved_recipe(socket, recipe_id)

        user_recipes =
          Users.list_user_saved_recipes(socket.assigns.current_user)
          |> Enum.map(fn x -> x.recipe_id end)

        recipe = Food.get_recipe!(recipe_id)
        socket = assign(socket, :user_recipes, user_recipes)
        socket = assign(socket, :current_user_recipes, user_recipes)
        socket = stream_insert(socket, :recipes, recipe)
        {:noreply, socket}
      end

      @impl true
      def handle_event("save_user_follow", %{"follow_id" => follow_id}, socket) do
        {follow_id, _ignore} = Integer.parse(follow_id)
        toggle_user_follow(socket, follow_id)
        user_follows = Users.list_user_follows(socket.assigns.current_user)
        user_follows = Enum.map(user_follows, fn x -> x.follow_id end)
        socket = assign(socket, :user_follows, user_follows)
        {:noreply, socket}
      end

      @impl true
      def handle_info(%{new_comment: comment}, socket) do
        recipe = socket.assigns.recipe
        recipe = Mehungry.Food.get_recipe!(recipe.id)
        IO.inspect(comment, label: "Recieved comment in lhelpres ")

        recipe = %Recipe{
          recipe
          | comments: Enum.sort_by(recipe.comments, & &1.updated_at)
        }

        user =
          case is_nil(Map.get(socket.assigns, :user, nil)) do
            true ->
              socket.assigns.current_user

            false ->
              socket.assigns.user
          end

        send_update(MehungryWeb.RecipeDetailsComponent, %{
          id: "recipe_details_component",
          recipe: recipe,
          user: user
        })

        {:noreply, socket}
      end
    end
  end

  def modal_large(assigns) do
    assigns = assign_new(assigns, :return_to, fn -> nil end)

    ~H"""
    <div id="modal" class="phx-modal fade-in w-full " phx-remove={hide_modal()}>
      <div
        id="modal-content"
        class="phx-modal-content-large fade-in-scale rounded-xl w-full"
        phx-click-away={JS.dispatch("click", to: "#close")}
        phx-window-keydown={JS.dispatch("click", to: "#close")}
        phx-key="escape"
      >
        <%= render_slot(@inner_block) %>
      </div>
    </div>
    """
  end

  defp hide_modal(js \\ %JS{}) do
    js
    |> JS.hide(to: "#modal", transition: "fade-out")
    |> JS.hide(to: "#modal-content", transition: "fade-out-scale")
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
