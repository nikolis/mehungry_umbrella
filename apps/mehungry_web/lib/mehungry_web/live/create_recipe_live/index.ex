defmodule MehungryWeb.CreateRecipeLive.Index do
  use MehungryWeb, :live_view
  use MehungryWeb.Presence, :user_tracking

  alias Mehungry.Food
  alias Mehungry.Food.{Recipe}

  alias Mehungry.Food.Recipe
  alias Mehungry.Accounts
  alias MehungryWeb.CreateRecipeLive.Components
  alias MehungryWeb.SimpleS3Upload

  def mount_search(_params, session, socket) do
    measurement_units = Food.get_measurement_unit_by_name("grammar")
    user = Accounts.get_user_by_session_token(session["user_token"])
    user_profile = Accounts.get_user_profile_by_user_id(user.id)

    {:ok,
     socket
     |> assign(:user, user)
     |> assign(:show, false)
     |> assign(:selected_ingredient, 1)
     |> assign(:user_profile, user_profile)
     |> assign(:ingredients, list_ingredients())
     |> assign(:measurement_units, measurement_units)
     |> assign(:page_title, "Share your recipes ")
     |> assign(:return_to_path, "/create_recipe")
     |> assign(:items, [
       %{id: 1, name: "easy"},
       %{id: 2, name: "medium"},
       %{id: 3, name: "difficult"}
     ])
     |> allow_upload(:image,
       accept: :any,
       max_entries: 1,
       max_file_size: 9_000_000,
       auto_upload: false,
       external: &presign_upload/2
     )}
  end

  defp presign_upload(entry, %{assigns: %{uploads: uploads}} = socket) do
    meta = SimpleS3Upload.meta(entry, uploads)
    {:ok, meta, socket}
  end

  ################################################################################## Actions #############################################################################################
  defp apply_action(socket, :index, _params) do
    recipe = %Recipe{steps: [], recipe_ingredients: [], language_name: "En"}
    maybe_track_user(%{}, socket)

    attrs =
      case Cachex.get(:create_recipe_cache, {__MODULE__, socket.assigns.user.id}) do
        {:ok, nil} ->
          %{}

        {:ok, attrs} ->
          attrs
      end

    socket
    |> assign(:recipe, recipe)
    |> init(recipe, attrs)
  end

  defp apply_action(socket, :edit, %{"recipe_id" => id}) do
    recipe = Food.get_recipe!(id)

    socket
    |> assign(:changeset, Food.change_recipe(recipe))
    |> assign(:recipe, recipe)
    |> init(recipe)
  end

  defp init(socket, base, attrs \\ %{}) do
    changeset =
      Recipe.changeset(base, attrs)
      |> struct!(action: :validate)

    assign(socket,
      base: base,
      changeset: changeset,
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

  @impl true
  def handle_params(params, uri, socket) do
    socket = assign(socket, :path, uri)
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  ################################################################################ Event Handling ###################################################################################
  use MehungryWeb.Searchable, :transfers_to_search

  def handle_event("clear-form", _, socket) do
    recipe = Food.get_recipe!(socket.assigns.recipe.id)
    socket = init(socket, recipe, %{})
    socket = assign(socket, :recipe, recipe)

    {:noreply, socket}
  end

  def handle_event("save", %{"recipe" => recipe_params}, socket) do
    save_recipe(socket, socket.assigns.live_action, recipe_params)
  end

  def handle_event("delete-image", _, socket) do
    # {:ok, recipe} = Food.update_recipe(socket.assigns.recipe, %{image_url: nil})
    recipe = %Recipe{socket.assigns.recipe | image_url: nil}

    {:noreply,
     socket
     |> assign(:recipe, recipe)
     |> init(recipe)}
  end

  def handle_event("add-step", _, socket) do
    existing = Ecto.Changeset.get_embed(socket.assigns.changeset, :steps)

    changeset =
      Ecto.Changeset.put_embed(
        socket.assigns.changeset,
        :steps,
        existing ++ [%{temp_id: get_temp_id()}]
      )

    socket = assign(socket, :changeset, changeset)

    {:noreply, socket}
  end

  @impl true
  def handle_event("remove-ingredient", %{"temp_id" => remove_id}, socket) do
    {_progress, recipe_ingredients} = remove_from_change(socket, remove_id)

    changeset =
      socket.assigns.changeset
      |> Ecto.Changeset.put_assoc(:recipe_ingredients, recipe_ingredients)

    {:noreply, assign(socket, changeset: changeset)}
  end

  def handle_event("remove-step", %{"temp_id" => remove_id}, socket) do
    {_progress, steps} = remove_from_change_step(socket, remove_id)

    changeset =
      socket.assigns.changeset
      |> Ecto.Changeset.put_embed(:steps, steps)

    {:noreply, assign(socket, changeset: changeset)}
  end

  @impl true
  def handle_event("other", _, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("validate", %{"recipe" => recipe_params}, socket) do
    recipe_params = Map.put(recipe_params, "language_name", "En")
    recipe_params = Map.put(recipe_params, "user_id", socket.assigns.current_user.id)

    changeset =
      socket.assigns.base
      |> Recipe.changeset(recipe_params)
      |> struct!(action: :validate)

    if(socket.assigns.live_action == :index) do
      Cachex.put(:create_recipe_cache, {__MODULE__, socket.assigns.user.id}, recipe_params)
    end

    {:noreply, assign(socket, :changeset, changeset)}
  end

  def handle_event("select_ingredient", %{"index" => index} = _params, socket) do
    socket = assign(socket, :selected_ingredient, String.to_integer(index))
    socket = assign(socket, :show, true)

    {:noreply, socket}
  end

  def handle_event("add-ingredient", _params, socket) do
    existing = Ecto.Changeset.get_assoc(socket.assigns.changeset, :recipe_ingredients)

    changeset =
      Ecto.Changeset.put_assoc(
        socket.assigns.changeset,
        :recipe_ingredients,
        existing ++ [%{temp_id: get_temp_id()}]
      )

    socket = assign(socket, :changeset, changeset)
    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :image, ref)}
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

  @impl true
  def handle_info({MehungryWeb.Onboarding.FormComponent, "profile-saved"}, socket) do
    user_profile = Accounts.get_user_profile_by_user_id(socket.assigns.user.id)

    {:noreply,
     socket
     |> assign(:user_profile, user_profile)}
  end

  ########################################################################################## Helper Function  ##########################################
  defp remove_from_change(socket, remove_id) do
    case Map.get(socket.assigns.changeset.changes, :recipe_ingredients, nil) do
      nil ->
        {:repeat, []}

      recipe_ingredient_changes ->
        original_length = length(recipe_ingredient_changes)

        result_changes =
          recipe_ingredient_changes
          |> Enum.reject(fn %{changes: recipe_ingredient} = _rest ->
            Map.get(recipe_ingredient, :temp_id, nil) == remove_id
          end)

        case length(result_changes) == original_length do
          true ->
            {:repeat, result_changes}

          false ->
            {:ok, result_changes}
        end
    end
  end

  defp remove_from_change_step(socket, remove_id) do
    case Map.get(socket.assigns.changeset.changes, :steps, nil) do
      nil ->
        {:repeat, []}

      steps_changes ->
        original_length = length(steps_changes)

        result_changes =
          steps_changes
          |> Enum.reject(fn %{changes: step} = _rest ->
            Map.get(step, :temp_id, nil) == remove_id
          end)

        case length(result_changes) == original_length do
          true ->
            {:repeat, result_changes}

          false ->
            {:ok, result_changes}
        end
    end
  end

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

  defp save_recipe(socket, :edit, recipe_params) do
    path =
      consume_uploaded_entries(
        socket,
        :image,
        fn %{url: url, key: key}, _entry ->
          #   dest = Path.join(Application.app_dir(:mehungry_web, "priv/static/images"), path)
          # You will need to create `priv/static/uploads` for `File.cp!/2` to work.
          #  if(File.exists?(Path.dirname(dest)) == false) do
          #   File.mkdir!(Path.dirname(dest))
          #   end

          #    File.cp!(path, dest)
          #    path_parts = String.split(dest, "/")

          #    dest =
          #      "/" <>
          #    Enum.at(path_parts, length(path_parts) - 4) <>
          #    "/" <>
          #    Enum.at(path_parts, length(path_parts) - 3) <>
          #    "/" <>
          #    Enum.at(path_parts, length(path_parts) - 2) <>
          #    "/" <> Enum.at(path_parts, length(path_parts) - 1)
          dest = url <> "/" <> key
          {:ok, dest}
        end
      )

    path = Enum.at(path, 0)
    socket = assign(socket, :image_upload, path)
    recipe_params = get_params_with_image(socket, recipe_params)
    recipe_params = Map.put(recipe_params, "language_name", "En")
    recipe_params = Map.put(recipe_params, "user_id", socket.assigns.current_user.id)

    case Food.update_recipe(socket.assigns.base, recipe_params) do
      {:ok, %Recipe{} = _recipe} ->
        {:noreply,
         socket
         |> put_flash(:info, "Recipe created succesfully")
         |> push_navigate(to: "/profile")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  defp save_recipe(socket, :index, recipe_params) do
    path =
      consume_uploaded_entries(
        socket,
        :image,
        fn %{url: url, key: key}, _entry ->
          # dest = Path.join(Application.app_dir(:mehungry_web, "priv/static/images"), path)
          # You will need to create `priv/static/uploads` for `File.cp!/2` to work.
          # if(File.exists?(Path.dirname(dest)) == false) do
          # File.mkdir!(Path.dirname(dest))
          # end

          # File.cp!(path, dest)
          # path_parts = String.split(dest, "/")

          # dest =
          # "/" <>
          #   Enum.at(path_parts, length(path_parts) - 4) <>
          #  "/" <>
          #   Enum.at(path_parts, length(path_parts) - 3) <>
          #  "/" <>
          #   Enum.at(path_parts, length(path_parts) - 2) <>
          #  "/" <> Enum.at(path_parts, length(path_parts) - 1)
          dest = url <> "/" <> key
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
         |> push_navigate(to: "/profile")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  def error_to_string(:too_large), do: "Too large"
  def error_to_string(:not_accepted), do: "You have selected an unacceptable file type"

  defp list_ingredients do
    Food.list_ingredients()
  end

  defp get_temp_id, do: :crypto.strong_rand_bytes(5) |> Base.url_encode64() |> binary_part(0, 5)
end
