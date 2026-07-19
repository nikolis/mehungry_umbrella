defmodule MehungryWeb.CreateRecipeLive.Index do
  use MehungryWeb, :live_view
  use MehungryWeb.Presence, :user_tracking

  require Logger

  alias Mehungry.Food
  alias Mehungry.Food.{Recipe, RecipeIngredient, Step}

  alias Mehungry.Food.Recipe
  alias Mehungry.Accounts
  alias MehungryWeb.SimpleS3Upload

  @impl true
  def mount(_params, session, socket) do
    user = Accounts.get_user_by_session_token(session["user_token"])
    user_profile = Accounts.get_user_profile_by_user_id(user.id)
    _grammar = Food.get_measurement_unit_by_name("grammar")

    {:ok,
     socket
     |> assign(:user, user)
     |> assign(:show, false)
     |> assign(:selected_ingredient, 1)
     |> assign(:user_profile, user_profile)
     |> assign(:ingredients, list_ingredients())
     |> assign(:measurement_units, nil)
     |> assign(:page_title, "Share your recipes ")
     |> assign(:return_to_path, "/create_recipe")
     |> assign(:active_step, 0)
     |> assign(:ai_generating, false)
     |> assign(:ai_task_ref, nil)
     |> assign(:ai_unmatched, [])
     |> assign(
       :ai_quota_exceeded,
       Mehungry.Subscriptions.check_quota(user.id, "recipe_generation") ==
         {:error, :quota_exceeded}
     )
     |> assign(:show_ai_panel, false)
     |> assign(:spoonacular_results, [])
     |> assign(:spoonacular_unmatched, [])
     |> assign(:spoonacular_search_loading, false)
     |> assign(:spoonacular_fetch_loading, false)
     |> assign(:show_spoonacular_modal, false)
     |> assign(:spoonacular_search_ref, nil)
     |> assign(:spoonacular_fetch_ref, nil)
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

  def handle_event("set_step", %{"step" => step}, socket) do
    {:noreply, assign(socket, active_step: String.to_integer(step))}
  end

  @impl true
  def handle_event("validate", %{"recipe" => recipe_params}, socket) do
    recipe_params =
      case socket.assigns[:current_language] do
        lang when lang not in [nil, "en"] -> Map.put(recipe_params, "language_name", lang)
        _ -> recipe_params
      end

    recipe_params = Map.put(recipe_params, "user_id", socket.assigns.current_user.id)

    changeset =
      socket.assigns.recipe
      |> Recipe.changeset(recipe_params)
      |> struct!(action: :validate)

    if(socket.assigns.live_action == :index) do
      Cachex.put(:create_recipe_cache, {__MODULE__, socket.assigns.user.id}, recipe_params)
    end

    {:noreply, assign(socket, :f, to_form(changeset))}
  end

  def handle_event("ai_generate", %{"prompt" => prompt}, socket) when prompt != "" do
    case Mehungry.Subscriptions.check_quota(socket.assigns.user.id, "recipe_generation") do
      :ok ->
        task = Task.async(fn -> Mehungry.AI.RecipeGenerator.run(prompt) end)

        {:noreply,
         socket
         |> assign(:ai_generating, true)
         |> assign(:ai_task_ref, task.ref)
         |> assign(:ai_unmatched, [])
         |> assign(:ai_quota_exceeded, false)}

      {:error, :quota_exceeded} ->
        {:noreply, assign(socket, :ai_quota_exceeded, true)}
    end
  end

  def handle_event("ai_generate", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("spoonacular_search", %{"query" => query}, socket) when query != "" do
    case spoonacular_rate_limit(socket.assigns.user.id) do
      :ok ->
        api_key = System.get_env("SPOONACULAR_API_KEY")
        task = Task.async(fn -> Mehungry.FoodData.SpoonacularImporter.search(query, api_key) end)

        {:noreply,
         assign(socket,
           spoonacular_search_loading: true,
           spoonacular_search_ref: task.ref
         )}

      {:error, :rate_limited} ->
        {:noreply, put_flash(socket, :error, "Too many searches. Please slow down for a moment.")}
    end
  end

  def handle_event("spoonacular_search", _params, socket), do: {:noreply, socket}

  def handle_event("spoonacular_select", %{"id" => id}, socket) do
    user_id = socket.assigns.user.id

    case spoonacular_rate_limit(user_id) do
      :ok ->
        api_key = System.get_env("SPOONACULAR_API_KEY")
        spoonacular_id = String.to_integer(id)

        task =
          Task.async(fn ->
            Mehungry.FoodData.SpoonacularImporter.fetch_for_form(spoonacular_id, user_id, api_key)
          end)

        {:noreply,
         assign(socket,
           spoonacular_fetch_loading: true,
           spoonacular_fetch_ref: task.ref,
           show_spoonacular_modal: false
         )}

      {:error, :rate_limited} ->
        {:noreply,
         socket
         |> assign(show_spoonacular_modal: false)
         |> put_flash(:error, "Too many imports. Please slow down for a moment.")}
    end
  end

  # Per-user fixed-window limit on the paid Spoonacular API (search + import
  # share one bucket) to prevent burning the shared key from free accounts.
  defp spoonacular_rate_limit(user_id) do
    Mehungry.RateLimit.hit("spoonacular:#{user_id}", 20, :timer.minutes(1))
  end

  def handle_event("close_spoonacular_modal", _, socket) do
    {:noreply, assign(socket, show_spoonacular_modal: false)}
  end

  def handle_event("add_ingredient", _params, socket) do
    current_params = socket.assigns.f.params || %{}
    add_ingredient(socket, current_params)
  end

  def handle_event("clear-form", _, socket) do
    # recipe = Food.get_recipe!(socket.assigns.recipe.id)
    socket = init(socket, %Recipe{}, %{})

    socket = assign(socket, :recipe, %Recipe{})

    {:noreply, socket}
  end

  def handle_event("save", %{"ingredient" => recipe_params}, socket) do
    handle_action(socket, recipe_params)
  end

  def handle_event("save", %{"recipe" => recipe_params}, socket) do
    handle_action(socket, recipe_params)
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

  def handle_event("select_ingredient", %{"index" => index} = _params, socket) do
    socket = assign(socket, :selected_ingredient, String.to_integer(index))
    socket = assign(socket, :show, true)

    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :image, ref)}
  end

  defp handle_action(socket, params) do
    case params["_action"] do
      "add_ingredient" ->
        add_ingredient(socket, params)

      "remove_ingredient:" <> index ->
        remove_ingredient(socket, params, index)

      "add_step" ->
        add_step(socket, params)

      "remove_step:" <> index ->
        remove_step(socket, params, index)

      _ ->
        save_recipe(socket, socket.assigns.live_action, params)
    end
  end

  defp remove_ingredient(socket, params, index) do
    portions =
      Map.get(params, "recipe_ingredients", %{})
      |> Map.delete(index)

    rebuild_form(socket, Map.put(params, "recipe_ingredients", portions))
  end

  defp remove_step(socket, params, index) do
    portions =
      Map.get(params, "steps", %{})
      |> Map.delete(index)

    rebuild_form(socket, Map.put(params, "steps", portions))
  end

  defp add_ingredient(socket, params) do
    ingredients = Map.get(params, "recipe_ingredients", %{})
    new_key = "#{map_size(ingredients)}"
    updated = Map.put(ingredients, new_key, %{})
    rebuild_form(socket, Map.put(params, "recipe_ingredients", updated))
  end

  defp add_step(socket, params) do
    steps = Map.get(params, "steps", %{})
    new_key = "#{map_size(steps)}"
    updated = Map.put(steps, new_key, %{})
    rebuild_form(socket, Map.put(params, "steps", updated))
  end

  @impl true
  def handle_params(params, uri, socket) do
    socket = assign(socket, :path, uri)
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  def get_params_with_image(socket, params) do
    if is_nil(Map.get(socket.assigns, :image_upload)) do
      params
    else
      Map.put(params, "image_url", socket.assigns.image_upload)
    end
  end

  defp apply_action(socket, :index, _params) do
    recipe = %Recipe{
      steps: [%Step{}],
      recipe_ingredients: [%RecipeIngredient{}],
      language_name: "En"
    }

    maybe_track_user(%{}, socket)

    attrs =
      case Cachex.get(:create_recipe_cache, {__MODULE__, socket.assigns.user.id}) do
        {:ok, nil} ->
          %{}

        {:ok, attrs} ->
          attrs
      end

    socket
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

    socket
    |> assign(:f, to_form(changeset))
    |> assign(:recipe, base)
  end

  defp rebuild_form(socket, params) do
    changeset =
      socket.assigns.recipe
      |> Food.change_recipe(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :f, to_form(changeset))}
  end

  defp presign_upload(entry, %{assigns: %{uploads: uploads}} = socket) do
    meta = SimpleS3Upload.meta(entry, uploads)
    {:ok, meta, socket}
  end

  ######################################################################################## External Signal Receivers #################################

  @impl true
  def handle_info({ref, result}, socket) when is_reference(ref) do
    Process.demonitor(ref, [:flush])

    cond do
      socket.assigns.ai_task_ref == ref ->
        case result do
          {:ok, attrs, unmatched} ->
            Mehungry.Subscriptions.record_usage(socket.assigns.user.id, "recipe_generation")
            recipe = %Recipe{steps: [], recipe_ingredients: [], language_name: "En"}

            {:noreply,
             socket
             |> assign(:ai_generating, false)
             |> assign(:ai_task_ref, nil)
             |> assign(:ai_unmatched, unmatched)
             |> init(recipe, attrs)}

          {:error, reason} ->
            {:noreply,
             socket
             |> assign(:ai_generating, false)
             |> assign(:ai_task_ref, nil)
             |> put_flash(:error, "Could not generate recipe: #{reason}")}
        end

      socket.assigns.spoonacular_search_ref == ref ->
        case result do
          {:ok, results} ->
            {:noreply,
             assign(socket,
               spoonacular_results: results,
               spoonacular_search_loading: false,
               show_spoonacular_modal: true,
               spoonacular_search_ref: nil
             )}

          {:error, reason} ->
            {:noreply,
             socket
             |> assign(:spoonacular_search_loading, false)
             |> assign(:spoonacular_search_ref, nil)
             |> put_flash(:error, "Spoonacular search failed: #{inspect(reason)}")}
        end

      socket.assigns.spoonacular_fetch_ref == ref ->
        case result do
          {:ok, attrs, unmatched} ->
            recipe = %Recipe{steps: [], recipe_ingredients: [], language_name: "En"}

            {:noreply,
             socket
             |> assign(:spoonacular_fetch_loading, false)
             |> assign(:spoonacular_fetch_ref, nil)
             |> assign(:spoonacular_unmatched, unmatched)
             |> init(recipe, attrs)}

          {:error, reason} ->
            {:noreply,
             socket
             |> assign(:spoonacular_fetch_loading, false)
             |> assign(:spoonacular_fetch_ref, nil)
             |> put_flash(:error, "Could not load recipe: #{inspect(reason)}")}
        end

      true ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _, _reason}, socket) when is_reference(ref) do
    if socket.assigns.ai_task_ref == ref do
      {:noreply,
       socket
       |> assign(:ai_generating, false)
       |> assign(:ai_task_ref, nil)
       |> put_flash(:error, "AI generation failed unexpectedly")}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:select_id, id, component_id}, socket) do
    send_update(MehungryWeb.IngredientComponent,
      id: component_id,
      new_ingredient_id: id
    )

    {:noreply, socket}
  end

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
    Logger.info("Maping: #{measurement_unit.name}")

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
          dest = url <> "/" <> key
          {:ok, dest}
        end
      )

    path = Enum.at(path, 0)
    socket = assign(socket, :image_upload, path)
    recipe_params = get_params_with_image(socket, recipe_params)

    recipe_params =
      case socket.assigns[:current_language] do
        lang when lang not in [nil, "en"] -> Map.put(recipe_params, "language_name", lang)
        _ -> recipe_params
      end

    recipe_params = Map.put(recipe_params, "user_id", socket.assigns.current_user.id)
    recipe_params = filter_empty_steps(recipe_params)

    case Food.update_recipe(socket.assigns.recipe, recipe_params) do
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
          dest = url <> "/" <> key
          {:ok, dest}
        end
      )

    path = Enum.at(path, 0)
    socket = assign(socket, :image_upload, path)
    recipe_params = get_params_with_image(socket, recipe_params)

    recipe_params =
      case socket.assigns[:current_language] do
        lang when lang not in [nil, "en"] -> Map.put(recipe_params, "language_name", lang)
        _ -> recipe_params
      end

    recipe_params = Map.put(recipe_params, "user_id", socket.assigns.current_user.id)
    recipe_params = filter_empty_steps(recipe_params)

    case Food.create_recipe(recipe_params) do
      {:ok, %Recipe{} = _recipe} ->
        Cachex.put(:create_recipe_cache, {__MODULE__, socket.assigns.user.id}, %{})

        {:noreply,
         socket
         |> put_flash(:info, "Recipe created succesfully")
         |> push_navigate(to: "/profile")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  defp filter_empty_steps(recipe_params) do
    steps = Map.get(recipe_params, "steps", %{})

    filtered =
      steps
      |> Enum.reject(fn {_k, v} -> is_nil(v["description"]) or v["description"] == "" end)
      |> Map.new()

    Map.put(recipe_params, "steps", filtered)
  end

  defp list_ingredients do
    Food.list_ingredients()
  end

  defp get_temp_id, do: :crypto.strong_rand_bytes(5) |> Base.url_encode64() |> binary_part(0, 5)
end
