defmodule MehungryWeb.LiveHelpers do
  @moduledoc false

  import Phoenix.Component

  alias Phoenix.LiveView.JS
  alias Mehungry.Users
  alias Mehungry.Food

  def hook_for_update_recipe_details_component do
    quote do
      @impl true
      def handle_event("recipe_detail_timing", %{"elapsed_ms" => elapsed_ms} = params, socket) do
        visit_id = Process.get(:current_visit_id)

        if visit_id do
          Mehungry.Meta.update_visit_recipe_timing(
            visit_id,
            elapsed_ms,
            Map.get(params, "server_ms"),
            Map.get(params, "recipe_id")
          )
        end

        {:noreply, socket}
      end

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
        case Enum.any?(socket.assigns.current_user_follows, fn x -> x == follow_id end) do
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
        if is_nil(socket.assigns[:current_user]) do
          {:noreply, assign(socket, :must_be_loged_in, 1)}
        else
          {recipe_id, _ignore} = Integer.parse(recipe_id)

          # Optimistic update: flip state in-memory (no DB re-query) so the heart
          # fill and like count move on the same round-trip, then persist.
          current = socket.assigns.current_user_recipes
          liked_now? = recipe_id not in current

          new_recipes =
            if liked_now?, do: [recipe_id | current], else: Enum.reject(current, &(&1 == recipe_id))

          socket =
            socket
            |> assign(:user_recipes, new_recipes)
            |> assign(:current_user_recipes, new_recipes)
            |> patch_posts_stream_like(recipe_id, liked_now?)

          # Persist by the pre-computed intent — do NOT reuse toggle_user_saved_recipe/2
          # here, since it re-reads current_user_recipes, which we just flipped.
          user_id = socket.assigns.current_user.id

          if liked_now? do
            Users.save_user_recipe(user_id, recipe_id)
          else
            Users.remove_user_saved_recipe(user_id, recipe_id)
          end

          {:noreply, socket}
        end
      end

      @impl true
      def handle_event("save_user_follow", %{"follow_id" => follow_id}, socket) do
        if is_nil(socket.assigns[:current_user]) do
          {:noreply, assign(socket, :must_be_loged_in, 1)}
        else
          {follow_id, _ignore} = Integer.parse(follow_id)

          # Optimistic update: flip the follow set in-memory, re-stream every
          # displayed card by this author so their Follow button flips, then persist.
          current = socket.assigns.current_user_follows
          following_now? = follow_id not in current

          new_follows =
            if following_now?, do: [follow_id | current], else: Enum.reject(current, &(&1 == follow_id))

          socket =
            socket
            |> assign(:current_user_follows, new_follows)
            |> restream_posts_by_author(follow_id)

          # Persist by the pre-computed intent — toggle_user_follow/2 would re-read
          # the current_user_follows we just flipped.
          user_id = socket.assigns.current_user.id

          if following_now? do
            Users.save_user_follow(user_id, follow_id)
          else
            Users.remove_user_follow(user_id, follow_id)
          end

          {:noreply, socket}
        end
      end

      # Home-feed only: patch the streamed post for this recipe so the like count
      # moves (only length/1 of reference.user_recipes is read on the card). No-op
      # for LiveViews that don't render a :posts stream over an all_posts assign.
      defp patch_posts_stream_like(socket, recipe_id, liked_now?) do
        if match?(%{posts: _}, socket.assigns[:streams] || %{}) and
             Map.has_key?(socket.assigns, :all_posts) do
          found =
            Enum.find(socket.assigns.all_posts, fn p ->
              p.reference_id == recipe_id and post_displayed?(socket, p.id)
            end)

          case found do
            nil ->
              socket

            post ->
              recipes = post.reference.user_recipes || []

              new_recipes =
                if liked_now?, do: [%{} | recipes], else: Enum.drop(recipes, 1)

              post = put_in(post.reference.user_recipes, new_recipes)

              socket
              |> assign(
                :all_posts,
                Enum.map(socket.assigns.all_posts, &if(&1.id == post.id, do: post, else: &1))
              )
              |> stream_insert(:posts, post)
          end
        else
          socket
        end
      end

      # Home-feed only: re-stream every displayed post authored by follow_id so
      # their Follow buttons pick up the updated current_user_follows assign.
      defp restream_posts_by_author(socket, follow_id) do
        if match?(%{posts: _}, socket.assigns[:streams] || %{}) and
             Map.has_key?(socket.assigns, :all_posts) do
          socket.assigns.all_posts
          |> Enum.filter(&(&1.user_id == follow_id and post_displayed?(socket, &1.id)))
          |> Enum.reduce(socket, fn post, acc -> stream_insert(acc, :posts, post) end)
        else
          socket
        end
      end

      # Only patch posts that are actually in the DOM. The home feed tracks this
      # in :displayed_post_ids; without that assign, assume displayed.
      defp post_displayed?(socket, post_id) do
        case socket.assigns[:displayed_post_ids] do
          nil -> true
          ids -> MapSet.member?(ids, post_id)
        end
      end

      @impl true
      def handle_info(%{new_comment: comment}, socket) do
        recipe_comments = Food.get_recipe_comments(comment.recipe_id)

        send_update(MehungryWeb.RecipeDetailsComponent, %{
          id: "recipe_details_component",
          recipe_comments: recipe_comments
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
        {render_slot(@inner_block)}
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
