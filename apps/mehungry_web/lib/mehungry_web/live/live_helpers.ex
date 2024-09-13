defmodule MehungryWeb.LiveHelpers do
  @moduledoc false

  import Phoenix.Component

  alias Phoenix.LiveView.JS
  alias Mehungry.Food.Recipe

  def hook_for_update_recipe_details_component do
    quote do
      @impl true
      def handle_info(%{new_comment: comment}, socket) do
        recipe = socket.assigns.recipe
        recipe = Mehungry.Food.get_recipe!(recipe.id)

        recipe = %Recipe{
          recipe
          | comments: Enum.sort_by(recipe.comments, & &1.updated_at)
        }

        send_update(MehungryWeb.RecipeDetailsComponent, %{
          id: "recipe_details_component",
          recipe: recipe,
          user: socket.assigns.user
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
