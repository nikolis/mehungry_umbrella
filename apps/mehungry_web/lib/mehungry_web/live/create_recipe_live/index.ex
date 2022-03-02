defmodule MehungryWeb.CreateRecipeLive.Index do
  use MehungryWeb, :live_view

  import Ecto

  alias Mehungry.Food
  alias Mehungry.Food.Recipe
  alias Mehungry.Food.Step
  alias Mehungry.Food.RecipeIngredient

  @step_title "Step Title"
  @step_description "The description of the step"

  @impl true
  def mount(_params, _session, socket) do
    attrs = %{uuid: Ecto.UUID.generate()}

    {:ok,
     socket
     |> assign(:recipes, list_recipes())
     |> assign(:ingredients, list_ingredients())
     |> assign(:recipe_ingredients, [])
     |> assign(:steps, [%{attributes: attrs, changeset: Food.change_step(%Step{}, %{})}])
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

  def map_recipe_ingredient(recipe_ingredients) do
    result =
      Enum.map(recipe_ingredients, fn ing ->
        ingredient = Food.get_ingredient(ing["ingredient_id"])
        measurement_unit = Food.get_measurement_unit!(ing["measurement_unit_id"])
        ing = Map.put(ing, "ingredient", ingredient.name)
        ing = Map.put(ing, "measurement_unit", measurement_unit.name)
      end)

    result
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

  @impl true
  def handle_event("add_step", _, socket) do
    attrs = %{uuid: Ecto.UUID.generate()}

    steps =
      socket.assigns.steps ++ [%{attributes: attrs, changeset: Food.change_step(%Step{}, %{})}]

    {:noreply,
     socket
     |> assign(:steps, steps)}
  end

  @impl true
  def handle_event("validate", %{"step" => step_params, "ident" => ident} = params, socket) do
    IO.inspect(params, label: "Params")
    [step] = Enum.filter(socket.assigns.steps, fn x -> x.attributes.uuid == ident end)
    rest = Enum.filter(socket.assigns.steps, fn x -> x.attributes.uuid != ident end)

    changeset =
      %Step{}
      |> Food.change_step(step_params)
      |> Map.put(:action, :validate)

    {:noreply,
     assign(socket, :steps, rest ++ [%{attributes: %{uuid: ident}, changeset: changeset}])}
  end

  defp apply_action(socket, :add_ingredient, _params) do
    uuid = Ecto.UUID.generate()

    socket
    |> assign(:page_title, "New Recipe")
    |> assign(:recipe_ingredient, %{"uuid" => uuid})
  end

  defp apply_action(socket, :edit_ingredient, %{"uuid" => uuid}) do
    recipe_ingredient =
      Enum.find(socket.assigns.recipe_ingredients, fn x -> x["uuid"] == uuid end)

    IO.inspect(recipe_ingredient, label: "Edit")

    socket
    |> assign(:page_title, "New Recipe")
    |> assign(:recipe_ingredient, recipe_ingredient)
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
  def handle_event("delete_step", %{"uuid" => uuid}, socket) do
    steps = Enum.filter(socket.assigns.steps, fn x -> x["uuid"] != uuid end)

    {:noreply,
     socket
     |> assign(:steps, steps)}
  end

  @impl true
  def handle_event("delete_ingredient", %{"uuid" => uuid}, socket) do
    IO.inspect(socket.assigns.recipe_ingredients, label: "Recipe ingredients before")

    recipe_ingredients =
      Enum.filter(socket.assigns.recipe_ingredients, fn x -> x["uuid"] != uuid end)

    IO.inspect(recipe_ingredients, label: "Recipe Ingredients after")

    {:noreply,
     socket
     |> assign(:recipe_ingredients, recipe_ingredients)}
  end

  @impl true
  def handle_info({:recipe_ingredient, recipe_ingredient_params}, socket) do
    recipe_ingredients =
      Enum.filter(socket.assigns.recipe_ingredients, fn x ->
        x["uuid"] != recipe_ingredient_params["uuid"]
      end)

    recipe_ingredients = recipe_ingredients ++ [recipe_ingredient_params]

    {:noreply,
     socket
     |> assign(:recipe_ingredients, recipe_ingredients)}
  end

  defp list_recipes do
    Food.list_recipes()
  end

  defp list_ingredients do
    Food.list_ingredients()
  end
end
