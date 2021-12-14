defmodule MehungryWeb.CreateRecipeLive.Index do
  use MehungryWeb, :live_view

  alias Mehungry.Food
  alias Mehungry.Food.Recipe
  alias Mehungry.Food.RecipeIngredient

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:recipes, list_recipes())
     |> assign(:ingredients, list_ingredients())
     |> allow_upload(:image,
       accept: ~w(.jpg .jpeg .png),
       max_entries: 1,
       auto_upload: true,
       progress: &handle_progress/3
     )}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp handle_progress(:image, entry, socket) do
    if entry.done? do
      path =
        consume_uploaded_entry(
          socket,
          entry,
          &upload_static_file(&1, socket)
        )

      {
        :noreply,
        socket
        # |> put_flash(:info, "file #{entry.client_name} uploaded")
        # |> update_changeset(:image_upload, path)
      }
    else
      {:noreply, socket}
    end
  end

  defp upload_static_file(%{path: path}, socket) do
    # Plug in your production image file persistence implementation here!
    dest = Path.join("priv/static/images", Path.basename(path))
    File.cp!(path, dest)
    Routes.static_path(socket, "/images/#{Path.basename(dest)}")
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Recipe")
    |> assign(:recipe, Food.get_recipe!(id))
  end

  defp apply_action(socket, :add_ingredient, _params) do
    socket
    |> assign(:page_title, "New Recipe")
    |> assign(:recipe_ingredient, %RecipeIngredient{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing Recipes")
    |> assign(:recipe, nil)
  end

  @impl true
  def handle_event(
        "new_ingredient_entry",
        %{
          "ingredient_id" => ingredient_id,
          "measurement_unit_id" => mu_id,
          "quantity" => quantity
        },
        socket
      ) do
    # recipe = Food.get_recipe!(id)
    # {:ok, _} = Food.delete_recipe(recipe)

    {:noreply, assign(socket, :recipes, list_recipes())}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    recipe = Food.get_recipe!(id)
    {:ok, _} = Food.delete_recipe(recipe)

    {:noreply, assign(socket, :recipes, list_recipes())}
  end

  defp list_recipes do
    Food.list_recipes()
  end

  defp list_ingredients do
    Food.list_ingredients()
  end
end
