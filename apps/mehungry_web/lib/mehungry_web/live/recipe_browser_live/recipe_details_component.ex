defmodule MehungryWeb.RecipeBrowserLive.RecipeDetailsComponent do
  use MehungryWeb, :live_component

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
          <img class=" rounded-2xl" src={@recipe.image_url} />
        </div>
        <div class="w-full">
          <.user_overview_card user={@recipe.user} . />
          <h3 class="m-2 mt-4  text-center w-full"><%= @recipe.title %></h3>
          <.recipe_details recipe={@recipe} nutrients={@nutrients} primary_size={@primary_size} ./>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    socket =
      assign(socket, assigns)

    {:ok, socket}
  end
end
