defmodule MehungryWeb.CreateRecipeLive.Index do
  use MehungryWeb, :live_view

  import Ecto

  alias Mehungry.Food
  alias Mehungry.Food.Recipe
  alias Mehungry.Food.Step
  alias Mehungry.Food.RecipeIngredient


  @impl true
  def mount(_params, _session, socket) do
    recipe = %Recipe{steps: [], recipe_ingredients: [] , language_name: "En"}
    {:ok,
     socket
     |> assign(:recipe, recipe)
     |> assign(:ingredients, list_ingredients())
     |> assign(:changeset, Food.change_recipe(recipe))
     |> allow_upload(:image,
       accept: ~w(.jpg .jpeg .png),
       max_entries: 1,
       max_file_size: 9_000_000,
       auto_upload: true,
       progress: &handle_progress/3
     )}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  def map_recipe_ingredient(recipe_ingredients) do
    ingredient = Food.get_ingredient(recipe_ingredients.ingredient_id)
    measurement_unit = Food.get_measurement_unit!(recipe_ingredients.measurement_unit_id)
    the_ing = %{temp_id: recipe_ingredients.temp_id, ingredient: ingredient.name, measurement_unit: measurement_unit.name, quantity: recipe_ingredients.quantity}
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
    #TODO Implement S3 upload before deployment
    dest = Path.join("priv/static/images", Path.basename(path))
    File.cp!(path, dest)
    Routes.static_path(socket, "/images/#{Path.basename(dest)}")
  end


  def handle_event("save", %{"recipe" => recipe_params}, socket) do
    save_recipe(socket, socket.assigns, recipe_params)
  end

  defp save_recipe(socket, action, recipe_params) do
    recipe_params = 
      if (! is_nil(Map.get(recipe_params, "steps"))) do
        Map.put(recipe_params, "steps", Enum.map(recipe_params["steps"], fn x -> elem(x, 1) end))
      else
        recipe_params
      end
     recipe_params = 
      if (! is_nil(Map.get(recipe_params, "recipe_ingredients"))) do
        Map.put(recipe_params, "recipe_ingredients", Enum.map(recipe_params["recipe_ingredients"], fn x -> elem(x, 1) end))
      else
        recipe_params
      end
 
    case Food.create_recipe(recipe_params) do
      {:ok, _category} ->
        {:noreply,
         socket
         |> put_flash(:info, "Recipe has been created ")
         |> push_redirect(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end


  def handle_event("remove-step", %{"remove" => remove_id}, socket) do
    steps =
      socket.assigns.changeset.changes.steps
      |> Enum.reject(fn %{data: step} ->
        step.temp_id == remove_id
      end)

    changeset =
      socket.assigns.changeset
      |> Ecto.Changeset.put_embed(:steps, steps)

    {:noreply, assign(socket, changeset: changeset)}
  end

  defp get_temp_id, do: :crypto.strong_rand_bytes(5) |> Base.url_encode64 |> binary_part(0, 5)


  @impl true
  def handle_event("validate", %{"recipe" => recipe_params} , socket) do
    ##TODO Investigate wtf is going on in here
    recipe_params = 
      if (! is_nil(Map.get(recipe_params, "steps"))) do
        Map.put(recipe_params, "steps", Enum.map(recipe_params["steps"], fn x -> elem(x, 1) end))
      else
        recipe_params
      end
    changeset = 
      socket.assigns.recipe
      |> Food.change_recipe(recipe_params)
      |> Map.put(:action, :validate)
    {:noreply, assign(socket, :changeset, changeset)}
  end

  defp apply_action(socket, :add_ingredient, _params) do
    temp_id = get_temp_id() 

    socket
    |> assign(:page_title, "New Recipe")
    |> assign(:recipe_ingredient, %{"temp_id" => temp_id})
  end


  defp apply_action(socket, :edit_ingredient, %{"temp_id" =>temp_id}) do
    recipe_ingredient_changeset =
      Enum.find(socket.assigns.changeset.changes.recipe_ingredients, fn x -> x.changes.temp_id == temp_id end)
   
    recipe_ingredient = Map.new(recipe_ingredient_changeset.changes, fn {k, v} -> {Atom.to_string(k), v} end) 

    socket
    |> assign(:page_title, "New Recipe")
    |> assign(:recipe_ingredient, recipe_ingredient)
  end

  defp apply_action(socket, :index, _params) do
    socket
  end

  @impl true
  def handle_event("delete_ingredient", %{"temp_id" => temp_id}, socket) do
    recipe_ingredients =
      Enum.filter(socket.assigns.recipe_ingredients, fn x -> x["temp_id"] != temp_id end)

    {:noreply,
     socket
     |> assign(:recipe_ingredients, recipe_ingredients)}
  end

  def handle_event("add-step", _, socket) do
    existing_steps = Map.get(socket.assigns.changeset.changes, :steps, socket.assigns.recipe.steps)
    
    steps =
      existing_steps
      |> Enum.concat([
        Food.change_step(%Step{temp_id: get_temp_id()}) # NOTE temp_id
      ])

    changeset =
      socket.assigns.changeset
      |> Ecto.Changeset.put_embed(:steps, steps)

    {:noreply, assign(socket, changeset: changeset)}
  end


  @impl true
  def handle_info({:recipe_ingredient, recipe_ingredient_params}, socket) do

    existing_ingredients = Map.get(socket.assigns.changeset.changes, :recipe_ingredients, socket.assigns.recipe.recipe_ingredients)
    existing_ingredients = Enum.map(existing_ingredients, fn x -> 
      x.changes
      |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end) 
    end)
    existing_ingredients = 
      case existing_ingredients do
        [] ->
          []
        reci_ingr_list ->
          Enum.filter(reci_ingr_list, fn x -> x["temp_id"] != recipe_ingredient_params["temp_id"] end)
      end

    recipe_ingredient_params = for {key, val} <- recipe_ingredient_params, into: %{}, do: {String.to_atom(key), val}

    ingredients =
      existing_ingredients ++ [recipe_ingredient_params]
    changeset =
      socket.assigns.changeset
      |> Ecto.Changeset.put_assoc(:recipe_ingredients, ingredients)
    
    {:noreply,
      socket
      |> assign(:changeset, changeset)
    }
  end

  defp list_recipes do
    Food.list_recipes()
  end

  defp list_ingredients do
    Food.list_ingredients()
  end
end
