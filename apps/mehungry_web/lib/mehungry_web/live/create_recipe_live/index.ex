defmodule MehungryWeb.CreateRecipeLive.Index do
  use MehungryWeb, :live_view

  alias Mehungry.Food
  alias Mehungry.Food.Recipe

  alias MehungryWeb.CreateRecipeLive.Components

  @impl true
  def mount(_params, _session, socket) do
    recipe = %Recipe{steps: [], recipe_ingredients: [], language_name: "En"}
    measurement_units = Food.list_measurement_units()

    {:ok,
     socket
     |> assign(:recipe, recipe)
     |> assign(:ingredients, list_ingredients())
     |> assign(:measurement_units, measurement_units)
     |> assign(:changeset, Food.change_recipe(recipe))
     |> allow_upload(:image,
       accept: :any,
       max_entries: 1,
       max_file_size: 9_000_000,
       auto_upload: true
       #       external: &presign_upload/2,
       #       progress: &handle_progress/3
     )
     |> init(recipe)}
  end

  defp init(socket, base) do
    changeset = Recipe.changeset(base, %{})

    assign(socket,
      base: base,
      form: to_form(changeset),
      # Reset form for LV
      id: "form-#{System.unique_integer()}"
    )
  end

  def get_params_with_image(socket, params) do
    if is_nil(Map.get(socket.assigns, :image_upload)) do
      params
    else
      Map.put(params, "image_url", socket.assigns.image_upload)
    end
  end

  ################################################################################## Actions #############################################################################################
  defp apply_action(socket, :index, _params) do
    socket
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  ################################################################################ Event Handling ###################################################################################
  use MehungryWeb.Searchable, :transfers_to_search

  def handle_event("save", %{"recipe" => recipe_params}, socket) do
    save_recipe(socket, socket.assigns, recipe_params)
  end

  def handle_event("add-step", _, socket) do
    socket =
      update(socket, :form, fn %{source: changeset} ->
        existing = Ecto.Changeset.get_embed(changeset, :steps)
        changeset = Ecto.Changeset.put_embed(changeset, :steps, existing ++ [%{}])
        to_form(changeset)
      end)

    {:noreply, socket}
  end

  def handle_event("remove-step", %{"index" => index}, socket) do
    index = String.to_integer(index)

    socket =
      update(socket, :form, fn %{source: changeset} ->
        existing = Ecto.Changeset.get_embed(changeset, :steps)
        {to_delete, rest} = List.pop_at(existing, index)

        steps =
          if Ecto.Changeset.change(to_delete).data.id do
            List.replace_at(existing, index, Ecto.Changeset.change(to_delete, delete: true))
          else
            rest
          end

        changeset
        |> Ecto.Changeset.put_embed(:steps, steps)
        |> to_form()
      end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("remove-ingredient", %{"index" => index}, socket) do
    index = String.to_integer(index)

    socket =
      update(socket, :form, fn %{source: changeset} ->
        existing = Ecto.Changeset.get_assoc(changeset, :recipe_ingredients)
        {to_delete, rest} = List.pop_at(existing, index)

        recipe_ingredients =
          if Ecto.Changeset.change(to_delete).data.id do
            List.replace_at(existing, index, Ecto.Changeset.change(to_delete, delete: true))
          else
            rest
          end

        changeset
        |> Ecto.Changeset.put_assoc(:recipe_ingredients, recipe_ingredients)
        |> to_form()
      end)

    {:noreply, socket}
  end

  def handle_event("add-ingredient", _params, socket) do
    socket =
      update(socket, :form, fn %{source: changeset} ->
        existing = Ecto.Changeset.get_assoc(changeset, :recipe_ingredients)
        changeset = Ecto.Changeset.put_assoc(changeset, :recipe_ingredients, existing ++ [%{}])
        to_form(changeset)
      end)

    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :image, ref)}
  end

  @impl true
  def handle_event("validate", %{"recipe" => recipe_params}, socket) do
    changeset =
      socket.assigns.base
      |> Recipe.changeset(recipe_params)
      |> struct!(action: :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def drop_hidden?(images) do
    case Enum.empty?(images) do
      true ->
        ""

      false ->
        "hidden"
    end
  end

  ######################################################################################## External Signal Receivers #################################

  @doc """
  Receiving the recipe_ingredient params from created in the RecipeIngredientComponent is this really needed
  """
  @impl true
  def handle_info({:recipe_ingredient, recipe_ingredient_params}, socket) do
    existing_ingredients =
      Map.get(
        socket.assigns.changeset.changes,
        :recipe_ingredients,
        socket.assigns.recipe.recipe_ingredients
      )

    existing_ingredients =
      Enum.map(existing_ingredients, fn x ->
        x.changes
        |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)
      end)

    existing_ingredients =
      case existing_ingredients do
        [] ->
          []

        reci_ingr_list ->
          Enum.filter(reci_ingr_list, fn x ->
            x["temp_id"] != recipe_ingredient_params["temp_id"]
          end)
      end

    ingredients = existing_ingredients ++ [recipe_ingredient_params]

    ingredients =
      Enum.map(ingredients, fn _x ->
        for {key, val} <- recipe_ingredient_params, into: %{}, do: {String.to_atom(key), val}
      end)

    changeset =
      socket.assigns.changeset
      |> Ecto.Changeset.put_assoc(:recipe_ingredients, ingredients)

    {:noreply,
     socket
     |> assign(:changeset, changeset)}
  end

  ########################################################################################## Helper Function  ##########################################

  def map_recipe_ingredient(recipe_ingredients) do
    ingredient = Food.get_ingredient(recipe_ingredients.ingredient_id)
    measurement_unit = Food.get_measurement_unit!(recipe_ingredients.measurement_unit_id)

    %{
      temp_id: recipe_ingredients.temp_id,
      ingredient: ingredient.name,
      measurement_unit: measurement_unit.name,
      quantity: recipe_ingredients.quantity
    }
  end

  defp save_recipe(socket, _action, recipe_params) do
    path =
      consume_uploaded_entries(
        socket,
        :image,
        fn %{path: path}, _entry ->
          dest = Path.join(Application.app_dir(:mehungry_web, "priv/static/images"), path)
          # You will need to create `priv/static/uploads` for `File.cp!/2` to work.
          if(File.exists?(Path.dirname(dest)) == false) do
            File.mkdir!(Path.dirname(dest))
          end

          File.cp!(path, dest)
          path_parts = String.split(dest, "/")

          dest =
            "/" <>
              Enum.at(path_parts, length(path_parts) - 4) <>
              "/" <>
              Enum.at(path_parts, length(path_parts) - 3) <>
              "/" <>
              Enum.at(path_parts, length(path_parts) - 2) <>
              "/" <> Enum.at(path_parts, length(path_parts) - 1)

          {:ok, dest}
        end
      )

    path = Enum.at(path, 0)
    socket = assign(socket, :image_upload, path)
    recipe_params = get_params_with_image(socket, recipe_params)
    recipe_params = Map.put(recipe_params, "language_name", "En")
    recipe_params = Map.put(recipe_params, "user_id", socket.assigns.current_user.id)

    case Food.create_recipe(recipe_params) do
      {:ok, %Recipe{} = _recipe} ->
        {:noreply,
         socket
         |> put_flash(:info, "Recipe created succesfully")
         |> push_redirect(to: "/browse")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  def error_to_string(:too_large), do: "Too large"
  def error_to_string(:not_accepted), do: "You have selected an unacceptable file type"

  defp list_ingredients do
    Food.list_ingredients()
  end
end
