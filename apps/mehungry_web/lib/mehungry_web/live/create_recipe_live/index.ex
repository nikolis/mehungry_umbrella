defmodule MehungryWeb.CreateRecipeLive.Index do
  use MehungryWeb, :live_view
  use MehungryWeb.Presence, :user_tracking

  require Logger

  alias Mehungry.Food
  alias Mehungry.Food.{Recipe, RecipeIngredient, Step}

  alias Mehungry.Food.Recipe
  alias Mehungry.Accounts

  @impl true
  def mount(_params, session, socket) do
    user = Accounts.get_user_by_session_token(session["user_token"])
    user_profile = Accounts.get_user_profile_by_user_id(user.id)
    _gram = Food.get_measurement_unit_by_name("gram")

    {:ok,
     socket
     |> assign(:user, user)
     |> assign(:user_profile, user_profile)
     |> assign(:page_title, "Share your recipes ")
     |> assign(:return_to_path, "/create_recipe")
     # Resolved ingredient_id → name cache for the live preview, so re-rendering
     # the preview on every keystroke doesn't re-query names it already knows.
     |> assign(:ingredient_names, %{})
     |> assign(:preview, empty_preview())
     |> assign(:ai_generating, false)
     |> assign(:ai_task_ref, nil)
     |> assign(:ai_unmatched, [])
     |> assign(:show_ai_ingredients_modal, false)
     |> assign(:ai_pending_prompt, nil)
     |> assign(:ai_existing_ingredients, [])
     |> assign(
       :ai_quota_exceeded,
       Mehungry.Subscriptions.check_quota(user.id, "recipe_generation") ==
         {:error, :quota_exceeded}
     )
     |> assign(:spoonacular_results, [])
     |> assign(:spoonacular_unmatched, [])
     |> assign(:spoonacular_search_loading, false)
     |> assign(:spoonacular_fetch_loading, false)
     |> assign(:show_spoonacular_modal, false)
     |> assign(:spoonacular_search_ref, nil)
     |> assign(:spoonacular_fetch_ref, nil)
     |> assign(:spoonacular_enabled, spoonacular_enabled?())
     |> allow_upload(:image,
       accept: :any,
       max_entries: 1,
       max_file_size: 9_000_000,
       auto_upload: false,
       external: &presign_upload/2
     )}
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
      |> Food.validation_changeset(recipe_params)
      |> struct!(action: :validate)

    if(socket.assigns.live_action == :index) do
      Cachex.put(:create_recipe_cache, {__MODULE__, socket.assigns.user.id}, recipe_params)
    end

    {:noreply, put_form(socket, changeset)}
  end

  def handle_event("ai_generate", %{"prompt" => prompt}, socket) when prompt != "" do
    case Mehungry.Subscriptions.check_quota(socket.assigns.user.id, "recipe_generation") do
      :ok ->
        case existing_ingredient_names(socket) do
          [] ->
            start_ai_generation(socket, prompt)

          names ->
            {:noreply,
             socket
             |> assign(:show_ai_ingredients_modal, true)
             |> assign(:ai_pending_prompt, prompt)
             |> assign(:ai_existing_ingredients, names)}
        end

      {:error, :quota_exceeded} ->
        {:noreply, assign(socket, :ai_quota_exceeded, true)}
    end
  end

  def handle_event("ai_generate", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("ai_import_url", %{"url" => url}, socket) do
    url = String.trim(url)

    cond do
      url == "" ->
        {:noreply, socket}

      not valid_http_url?(url) ->
        {:noreply,
         put_flash(socket, :error, gettext("Please enter a valid http(s) recipe link."))}

      true ->
        case Mehungry.Subscriptions.check_quota(socket.assigns.user.id, "recipe_generation") do
          :ok -> start_ai_url_import(socket, url)
          {:error, :quota_exceeded} -> {:noreply, assign(socket, :ai_quota_exceeded, true)}
        end
    end
  end

  def handle_event("ai_import_url", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("ai_generate_confirm", %{"keep" => keep}, socket) do
    prompt = socket.assigns.ai_pending_prompt || ""
    names = socket.assigns.ai_existing_ingredients

    description =
      if keep == "true" and names != [] do
        prompt <>
          "\n\nTry to use these ingredients I already have where they fit naturally: " <>
          Enum.join(names, ", ") <> "."
      else
        prompt
      end

    start_ai_generation(socket, description)
  end

  def handle_event("ai_cancel_generate", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_ai_ingredients_modal, false)
     |> assign(:ai_pending_prompt, nil)}
  end

  def handle_event("spoonacular_search", _params, %{assigns: %{spoonacular_enabled: false}} = socket),
    do: {:noreply, socket}

  def handle_event("spoonacular_search", %{"query" => query}, socket) when query != "" do
    with :ok <- spoonacular_rate_limit(socket.assigns.user.id),
         {:ok, api_key} <- spoonacular_api_key() do
      task = Task.async(fn -> Mehungry.FoodData.SpoonacularImporter.search(query, api_key) end)

      {:noreply,
       assign(socket,
         spoonacular_search_loading: true,
         spoonacular_search_ref: task.ref
       )}
    else
      {:error, :rate_limited} ->
        {:noreply, put_flash(socket, :error, "Too many searches. Please slow down for a moment.")}

      {:error, :missing_api_key} ->
        {:noreply, put_flash(socket, :error, spoonacular_unavailable_message())}
    end
  end

  def handle_event("spoonacular_search", _params, socket), do: {:noreply, socket}

  def handle_event("spoonacular_select", _params, %{assigns: %{spoonacular_enabled: false}} = socket),
    do: {:noreply, socket}

  def handle_event("spoonacular_select", %{"id" => id}, socket) do
    user_id = socket.assigns.user.id

    with :ok <- spoonacular_rate_limit(user_id),
         {:ok, api_key} <- spoonacular_api_key() do
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
    else
      {:error, :rate_limited} ->
        {:noreply,
         socket
         |> assign(show_spoonacular_modal: false)
         |> put_flash(:error, "Too many imports. Please slow down for a moment.")}

      {:error, :missing_api_key} ->
        {:noreply,
         socket
         |> assign(show_spoonacular_modal: false)
         |> put_flash(:error, spoonacular_unavailable_message())}
    end
  end

  def handle_event("close_spoonacular_modal", _, socket) do
    {:noreply, assign(socket, show_spoonacular_modal: false)}
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
    %Recipe{} = current_recipe = socket.assigns.recipe
    recipe = %Recipe{current_recipe | image_url: nil}

    {:noreply,
     socket
     |> assign(:recipe, recipe)
     |> init(recipe)}
  end

  @impl true
  def handle_event("other", _, socket) do
    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :image, ref)}
  end

  # Spoonacular recipe import is **shadowed** — kept in the codebase but not
  # surfaced to any user — because persisting full Spoonacular recipes likely
  # violates their TOS (the public-domain MyPlate importer is the sanctioned
  # path). Flip to `true` (or read a config/env flag here) to re-enable the UI +
  # its handlers. Gates both the template block and the event handlers.
  defp spoonacular_enabled?, do: false

  # Per-user fixed-window limit on the paid Spoonacular API (search + import
  # share one bucket) to prevent burning the shared key from free accounts.
  defp spoonacular_rate_limit(user_id) do
    Mehungry.RateLimit.hit("spoonacular:#{user_id}", 20, :timer.minutes(1))
  end

  # Fail fast (and visibly) when the shared Spoonacular key isn't configured,
  # instead of firing a request that comes back as an opaque "HTTP 401".
  defp spoonacular_api_key do
    case System.get_env("SPOONACULAR_API_KEY") do
      key when is_binary(key) and key != "" -> {:ok, key}
      _ -> {:error, :missing_api_key}
    end
  end

  defp spoonacular_unavailable_message,
    do: "Recipe import is temporarily unavailable. Please try again later."

  # Ingredient/step rows are added and removed through the `sort_param`/`drop_param`
  # mechanism declared on `Recipe.changeset`: "add" appends a sentinel to the
  # collection's sort param so cast_assoc/cast_embed materialises a new empty row;
  # "remove" appends the clicked row index to the drop param so it's dropped
  # (persisted ingredient rows deleted via `on_replace: :delete`). Both only rebuild
  # the in-memory form — nothing persists until Save (the `_` clause). Because every
  # add/remove is a full form submit, the complete current row set is always carried,
  # so existing rows can never be lost.
  defp handle_action(socket, params) do
    case params["_action"] do
      "add_ingredient" ->
        rebuild_form(socket, add_row(params, "recipe_ingredients"))

      "remove_ingredient:" <> index ->
        rebuild_form(socket, drop_row(params, "recipe_ingredients", index))

      "add_step" ->
        rebuild_form(socket, add_row(params, "steps"))

      "remove_step:" <> index ->
        rebuild_form(socket, drop_row(params, "steps", index))

      _ ->
        save_recipe(socket, socket.assigns.live_action, params)
    end
  end

  # Append a sentinel to `<field>_sort` so cast_assoc/cast_embed adds one new empty row.
  defp add_row(params, field) do
    Map.update(params, "#{field}_sort", ["new"], &(&1 ++ ["new"]))
  end

  # Append the row index to `<field>_drop` so cast_assoc/cast_embed drops that row.
  defp drop_row(params, field, index) do
    Map.update(params, "#{field}_drop", [index], &(&1 ++ [index]))
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
    recipe = Food.get_recipe!(id) |> put_unit_selections()

    socket
    |> assign(:changeset, Food.change_recipe(recipe))
    |> assign(:recipe, recipe)
    |> init(recipe)
  end

  # Seeds each recipe ingredient's virtual `unit_selection` from its persisted
  # unit/portion so the unit dropdown shows the saved choice when editing.
  defp put_unit_selections(%Recipe{recipe_ingredients: ris} = recipe) when is_list(ris) do
    %Recipe{
      recipe
      | recipe_ingredients:
          Enum.map(ris, fn %RecipeIngredient{} = ri ->
            %RecipeIngredient{ri | unit_selection: RecipeIngredient.unit_selection_value(ri)}
          end)
    }
  end

  defp put_unit_selections(recipe), do: recipe

  defp init(socket, base, attrs \\ %{}) do
    changeset =
      Recipe.changeset(base, attrs)
      |> struct!(action: :validate)

    socket
    |> assign(:recipe, base)
    |> put_form(changeset)
  end

  defp rebuild_form(socket, params) do
    changeset =
      socket.assigns.recipe
      |> Food.validation_changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, put_form(socket, changeset)}
  end

  # Single chokepoint for publishing a changeset to the form: assigns `@f` and
  # refreshes the live preview (`@preview`) from the same changeset so the
  # right-hand card never drifts from the form the user is editing.
  defp put_form(socket, changeset) do
    socket
    |> assign(:f, to_form(changeset))
    |> assign_preview(changeset)
  end

  # Projects the current changeset into the flat `@preview` map the
  # `recipe_preview/1` component renders — no changeset digging or DB queries in
  # the template. Ingredient names are resolved through (and memoised into) the
  # `@ingredient_names` cache so typing in any field doesn't re-query names.
  defp assign_preview(socket, %Ecto.Changeset{} = changeset) do
    ingredient_changesets =
      changeset
      |> Ecto.Changeset.get_assoc(:recipe_ingredients)
      |> Enum.reject(&(&1.action in [:replace, :delete]))

    ids =
      ingredient_changesets
      |> Enum.map(&Ecto.Changeset.get_field(&1, :ingredient_id))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    names = resolve_names(ids, socket.assigns.ingredient_names)

    ingredients =
      ingredient_changesets
      |> Enum.map(fn ri ->
        id = Ecto.Changeset.get_field(ri, :ingredient_id)

        %{
          name: id && Map.get(names, id),
          quantity: Ecto.Changeset.get_field(ri, :quantity)
        }
      end)
      |> Enum.filter(& &1.name)

    steps =
      changeset
      |> Ecto.Changeset.get_embed(:steps)
      |> Enum.reject(&(&1.action in [:replace, :delete]))
      |> Enum.map(fn step ->
        %{
          title: Ecto.Changeset.get_field(step, :title),
          description: Ecto.Changeset.get_field(step, :description)
        }
      end)
      |> Enum.filter(&present?(&1.description))

    preview = %{
      title: Ecto.Changeset.get_field(changeset, :title),
      description: Ecto.Changeset.get_field(changeset, :description),
      image_url: Ecto.Changeset.get_field(changeset, :image_url),
      cooking_time: Ecto.Changeset.get_field(changeset, :cooking_time_lower_limit),
      prep_time: Ecto.Changeset.get_field(changeset, :preperation_time_lower_limit),
      servings: Ecto.Changeset.get_field(changeset, :servings),
      difficulty: Ecto.Changeset.get_field(changeset, :difficulty),
      ingredients: ingredients,
      steps: steps,
      valid?: changeset.valid?
    }

    assign(socket, ingredient_names: names, preview: preview)
  end

  # Only query names for ids not already in the cache.
  defp resolve_names(ids, cache) do
    (ids -- Map.keys(cache))
    |> Enum.reduce(cache, fn id, acc ->
      case Food.get_ingredient(id) do
        nil -> acc
        ingredient -> Map.put(acc, id, ingredient.name)
      end
    end)
  end

  defp present?(value), do: value not in [nil, ""]

  defp empty_preview do
    %{
      title: nil,
      description: nil,
      image_url: nil,
      cooking_time: nil,
      prep_time: nil,
      servings: nil,
      difficulty: nil,
      ingredients: [],
      steps: [],
      valid?: false
    }
  end

  defp presign_upload(entry, %{assigns: %{uploads: uploads}} = socket) do
    meta =
      MehungryWeb.Uploads.meta(
        entry,
        MehungryWeb.Uploads.recipe_image_key(entry),
        uploads.image.max_file_size
      )

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
            language_name =
              recipe_language_name(socket.assigns[:ai_language] || socket.assigns[:current_language])

            attrs =
              attrs
              |> Map.put("user_id", socket.assigns.user.id)
              |> Map.put("language_name", language_name)

            case Food.create_recipe(attrs) do
              {:ok, recipe} ->
                Mehungry.Subscriptions.record_usage(
                  socket.assigns.user.id,
                  "recipe_generation"
                )

                Logger.info(
                  "Recipe created (AI): id=#{recipe.id} user_id=#{socket.assigns.user.id} title=#{inspect(recipe.title)}"
                )

                Cachex.put(:create_recipe_cache, {__MODULE__, socket.assigns.user.id}, %{})

                {:noreply,
                 socket
                 |> assign(:ai_generating, false)
                 |> assign(:ai_task_ref, nil)
                 |> push_navigate(to: ~p"/create_recipe/#{recipe.id}")}

              {:error, %Ecto.Changeset{} = changeset} ->
                # Safety net: the AI omitted a required field (e.g. cook time) or
                # returned no valid ingredients. Fall back to loading the draft
                # into the form so the generated content isn't lost.
                Logger.warning(
                  "Recipe creation failed (AI): user_id=#{socket.assigns.user.id} errors=#{inspect(changeset_error_map(changeset))}"
                )

                recipe = %Recipe{steps: [], recipe_ingredients: [], language_name: language_name}

                {:noreply,
                 socket
                 |> assign(:ai_generating, false)
                 |> assign(:ai_task_ref, nil)
                 |> assign(:ai_unmatched, unmatched)
                 |> put_flash(
                   :error,
                   "Your recipe was generated but needs a couple of fixes before saving."
                 )
                 |> init(recipe, attrs)}
            end

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

  @impl true
  def handle_info({MehungryWeb.Onboarding.FormComponent, "profile-saved"}, socket) do
    user_profile = Accounts.get_user_profile_by_user_id(socket.assigns.user.id)

    {:noreply,
     socket
     |> assign(:user_profile, user_profile)}
  end

  ########################################################################################## Helper Function  ##########################################
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
        fn %{public_url: public_url}, _entry ->
          {:ok, public_url}
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
    recipe_params = recipe_params |> filter_empty_steps() |> drop_sort_drop_params()

    case Food.update_recipe(socket.assigns.recipe, recipe_params) do
      {:ok, %Recipe{} = recipe} ->
        Logger.info(
          "Recipe updated: id=#{recipe.id} user_id=#{socket.assigns.current_user.id} title=#{inspect(recipe.title)}"
        )

        {:noreply,
         socket
         |> put_flash(:info, "Recipe updated succesfully")
         |> push_navigate(to: "/profile")}

      {:error, %Ecto.Changeset{} = changeset} ->
        Logger.warning(
          "Recipe update failed: recipe_id=#{socket.assigns.recipe.id} user_id=#{socket.assigns.current_user.id} errors=#{inspect(changeset_error_map(changeset))}"
        )

        {:noreply,
         socket
         |> assign(:changeset, changeset)
         |> put_form(%{changeset | action: :update})
         |> put_flash(:error, save_error_flash(changeset))}
    end
  end

  defp save_recipe(socket, :index, recipe_params) do
    path =
      consume_uploaded_entries(
        socket,
        :image,
        fn %{public_url: public_url}, _entry ->
          {:ok, public_url}
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
    recipe_params = recipe_params |> filter_empty_steps() |> drop_sort_drop_params()

    case Food.create_recipe(recipe_params) do
      {:ok, %Recipe{} = recipe} ->
        Cachex.put(:create_recipe_cache, {__MODULE__, socket.assigns.user.id}, %{})

        Logger.info(
          "Recipe created: id=#{recipe.id} user_id=#{socket.assigns.current_user.id} title=#{inspect(recipe.title)}"
        )

        {:noreply,
         socket
         |> MehungryWeb.GoogleAnalytics.track("create_recipe", %{recipe_id: recipe.id})
         |> put_flash(:info, "Recipe created succesfully")
         |> push_navigate(to: "/profile")}

      {:error, %Ecto.Changeset{} = changeset} ->
        Logger.warning(
          "Recipe creation failed: user_id=#{socket.assigns.current_user.id} errors=#{inspect(changeset_error_map(changeset))}"
        )

        {:noreply,
         socket
         |> assign(:changeset, changeset)
         |> put_form(%{changeset | action: :insert})
         |> put_flash(:error, save_error_flash(changeset))}
    end
  end

  # Turns a rejected save changeset into a specific, user-facing flash naming the
  # actual blockers (missing fields, unit/portion problems, duplicate title) —
  # these errors are otherwise invisible in the form. Shares the same formatter
  # as the Review & Save panel so the two never diverge.
  defp save_error_flash(changeset) do
    case MehungryWeb.RecipeFormComponent.save_error_messages(changeset) do
      [] -> "Couldn't save the recipe — please review the form and try again."
      msgs -> "Couldn't save: " <> Enum.join(msgs, " · ")
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

  # The `*_sort`/`*_drop` params only exist to drive in-memory add/remove of rows
  # (see `handle_action`). On a real save they must be stripped so cast_assoc/
  # cast_embed fall back to normal matching (by `id` / replace) rather than
  # reordering against a step list that `filter_empty_steps` may have pruned —
  # which would otherwise re-materialise an empty step and fail validation.
  defp drop_sort_drop_params(recipe_params) do
    Map.drop(recipe_params, [
      "recipe_ingredients_sort",
      "recipe_ingredients_drop",
      "steps_sort",
      "steps_drop"
    ])
  end

  # Decides the output language of a generated recipe. Greek when the app is in the
  # Greek locale OR the prompt itself is written in Greek — so "prompt in Greek →
  # recipe in Greek" holds regardless of which UI locale the user happens to be in.
  # The generation loop still runs in English (see RecipeAgent); this only selects
  # whether the final prose is translated to Greek.
  defp output_language("el", _description), do: "el"
  defp output_language(_locale, description), do: if(greek?(description), do: "el", else: "en")

  # True if the text contains any Greek-script character.
  defp greek?(text) when is_binary(text), do: String.match?(text, ~r/\p{Greek}/u)
  defp greek?(_), do: false

  # Maps the viewer's content locale ("en"/"el"/nil) to the `languages.name` FK the
  # recipe row carries. The table holds legacy names "En"/"Gr" (not ISO codes), so
  # a Greek-locale generation must be tagged "Gr" — tagging the Greek prose "En"
  # would mislabel it for localization/display. Defaults to English.
  defp recipe_language_name("el"), do: "Gr"
  defp recipe_language_name(_), do: "En"

  # Launches the background generation task and enters the frozen state. Re-checks
  # quota defensively so a stale modal can't slip past the limit.
  defp start_ai_generation(socket, description) do
    case Mehungry.Subscriptions.check_quota(socket.assigns.user.id, "recipe_generation") do
      :ok ->
        language = output_language(socket.assigns[:current_language], description)
        task = Task.async(fn -> Mehungry.AI.RecipeGenerator.run(description, language) end)

        {:noreply,
         socket
         |> assign(:ai_generating, true)
         |> assign(:ai_task_ref, task.ref)
         |> assign(:ai_language, language)
         |> assign(:show_ai_ingredients_modal, false)
         |> assign(:ai_pending_prompt, nil)
         |> assign(:ai_unmatched, [])
         |> assign(:ai_quota_exceeded, false)}

      {:error, :quota_exceeded} ->
        {:noreply,
         socket
         |> assign(:show_ai_ingredients_modal, false)
         |> assign(:ai_quota_exceeded, true)}
    end
  end

  # Fetches + reproduces a recipe from a URL on a background task. Reuses the same
  # `:ai_task_ref`/`:ai_generating` plumbing as text generation, so the existing
  # `handle_info` success path (persist, record_usage, navigate, changeset fallback)
  # handles the `{:ok, attrs, unmatched}` result with no extra code.
  defp start_ai_url_import(socket, url) do
    case Mehungry.Subscriptions.check_quota(socket.assigns.user.id, "recipe_generation") do
      :ok ->
        task = Task.async(fn -> Mehungry.AI.RecipeUrlImport.run(url) end)

        {:noreply,
         socket
         |> assign(:ai_generating, true)
         |> assign(:ai_task_ref, task.ref)
         |> assign(:ai_language, "en")
         |> assign(:show_ai_ingredients_modal, false)
         |> assign(:ai_pending_prompt, nil)
         |> assign(:ai_unmatched, [])
         |> assign(:ai_quota_exceeded, false)}

      {:error, :quota_exceeded} ->
        {:noreply, assign(socket, :ai_quota_exceeded, true)}
    end
  end

  defp valid_http_url?(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        true

      _ ->
        false
    end
  end

  # Names of the ingredients the user has already added to the in-progress form,
  # read from the changeset behind `@f`. Empty list when there are none (or no
  # form yet), which is the signal to skip the confirmation modal.
  defp existing_ingredient_names(socket) do
    case socket.assigns[:f] do
      %{source: %Ecto.Changeset{} = changeset} ->
        changeset
        |> Ecto.Changeset.get_assoc(:recipe_ingredients)
        |> Enum.map(&Ecto.Changeset.get_field(&1, :ingredient_id))
        |> Enum.reject(&is_nil/1)
        |> Enum.map(&Food.get_ingredient/1)
        |> Enum.reject(&is_nil/1)
        |> Enum.map(& &1.name)
        |> Enum.uniq()

      _ ->
        []
    end
  end

  # Flattens a changeset's errors into a plain map for readable log lines.
  defp changeset_error_map(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
