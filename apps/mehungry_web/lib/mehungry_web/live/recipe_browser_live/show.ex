defmodule MehungryWeb.RecipeBrowseLive.Show do
  use MehungryWeb, :live_component
  Phoenix.LiveView.JS

  # alias Mehungry.Food
  alias Mehungry.Food.Recipe
  alias MehungryWeb.ImageProcessing

  # alias Phoenix.LiveView.JS

  @impl true
  def update(%{recipe: recipe} = assigns, socket) do
    recipe = handle_recipe_image(recipe)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:recipe, recipe)}
  end

  defp handle_recipe_image(recipe) do
    return = ImageProcessing.resize_details(recipe.image_url, 100, 100)
    %Recipe{recipe | detail_image_url: return}
  end

  """
  defp hide_modal(js \\ %JS{}) do
    js
    |> JS.hide(to: "#modal", transition: "fade-out")
    |> JS.hide(to: "#modal-content", transition: "fade-out-scale")
  end
  """
end
