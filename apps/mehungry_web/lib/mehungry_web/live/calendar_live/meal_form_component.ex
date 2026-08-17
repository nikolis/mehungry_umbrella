defmodule MehungryWeb.CalendarLive.MealFormComponent do
  use MehungryWeb, :live_component

  import MehungryWeb.CoreComponents

  alias Mehungry.History.UserMeal
  alias Mehungry.History.IngredientUserMeal

  alias Mehungry.Food
  alias Mehungry.Food.IngredientPortion
  alias Mehungry.History
  alias MehungryWeb.CalendarLive.Components

  # Sent (via `send_update/2` from the ingredient picker's `select_function`)
  # when an ingredient row's ingredient changes: refresh just that row's unit
  # dropdown to the newly chosen ingredient's portions. This also re-renders the
  # row's `inputs_for` form, so we first stamp the picked `ingredient_id` into
  # the parent changeset — otherwise the re-rendered ingredient picker would
  # recompute its selected item from a changeset that hasn't caught up yet and
  # blank the selection.
  @impl true
  def update(%{ingredient_selected: {index, ingredient_id}}, socket) do
    options = unit_options(ingredient_id)

    socket =
      socket
      |> assign(
        :unit_options_by_index,
        Map.put(socket.assigns.unit_options_by_index, index, options)
      )
      |> update(:form, fn %{source: changeset} ->
        existing = Ecto.Changeset.get_assoc(changeset, :ingredient_user_meals)

        updated =
          List.update_at(existing, index, fn row_cs ->
            Ecto.Changeset.put_change(row_cs, :ingredient_id, ingredient_id)
          end)

        changeset
        |> Ecto.Changeset.put_assoc(:ingredient_user_meals, updated)
        |> to_form()
      end)

    {:ok, socket}
  end

  @impl true
  def update(%{id: id, title: title, dates: dates, current_user: user} = assigns, socket) do
    default_attrs = %{
      start_dt: dates.start,
      title: title,
      meal_type: Map.get(assigns, :meal_type),
      user_id: user.id
    }

    base_user_meal =
      case id do
        :new ->
          struct(UserMeal)

        id ->
          user.id
          |> History.get_user_meal_raw!(id)
          |> seed_ingredient_unit_selections()
      end

    recipes = Food.list_user_recipes_for_selection(assigns.current_user)
    incomplete_user_meals = list_recipe_incomplete_user_meals(assigns.current_user)
    # Ingredient rows now pick an ingredient *portion* ("1 cup", "1 medium")
    # rather than only grams. Each row's dropdown is scoped to its ingredient's
    # portions (built in `unit_options/1`); `gram_options` is the fallback for a
    # row with no ingredient chosen yet, and `unit_options_by_index` caches the
    # per-row option lists so we don't re-query on every render.
    gram_options = gram_options()
    unit_options_by_index = build_unit_options_by_index(base_user_meal)

    recipe_ids = Enum.map(recipes, fn x -> x.id end)

    recipe_user_meal_ids =
      case incomplete_user_meals do
        [] ->
          []

        other ->
          Enum.map(other, fn x -> x.id end)
      end

    socket =
      socket
      |> assign(assigns)
      |> assign(:recipe_user_meal_ids, recipe_user_meal_ids)
      |> assign(:recipe_user_meals, incomplete_user_meals)
      |> assign(:recipes, recipes)
      |> assign(:gram_options, gram_options)
      |> assign(:unit_options_by_index, unit_options_by_index)
      |> assign(:user_meal, base_user_meal)
      |> assign(:recipe_ids, recipe_ids)
      |> assign(:mode, initial_mode(id, base_user_meal))

    {:ok, init(socket, base_user_meal, default_attrs)}
  end

  # Seeds each persisted ingredient row's virtual `unit_selection` from its
  # stored FKs so the unit dropdown shows the right option when editing.
  defp seed_ingredient_unit_selections(%UserMeal{ingredient_user_meals: iums} = meal)
       when is_list(iums) do
    %{
      meal
      | ingredient_user_meals:
          Enum.map(iums, fn ium ->
            %{ium | unit_selection: IngredientUserMeal.unit_selection_value(ium)}
          end)
    }
  end

  defp seed_ingredient_unit_selections(meal), do: meal

  # Precomputes the per-row unit dropdown options keyed by the row's `inputs_for`
  # index (its position in the ingredient list). New meals have no persisted rows
  # yet, so the map starts empty and rows fall back to `gram_options`.
  defp build_unit_options_by_index(%UserMeal{ingredient_user_meals: iums}) when is_list(iums) do
    iums
    |> Enum.with_index()
    |> Map.new(fn {ium, idx} -> {idx, unit_options(ium.ingredient_id)} end)
  end

  defp build_unit_options_by_index(_meal), do: %{}

  # Builds the unit dropdown options for an ingredient, mirroring the recipe
  # form's `IngredientComponent`: every portion becomes an option (values encode
  # `measurement_unit_id`, or `-portion_id` for description-only portions), with
  # "gram" always appended so a portion-less ingredient stays usable.
  defp unit_options(nil), do: gram_options()

  defp unit_options(ingredient_id) do
    portion_options =
      ingredient_id
      |> Food.get_measurement_unit_portions_for_ingredient()
      |> Enum.map(fn portion ->
        value = if portion.measurement_unit_id, do: portion.measurement_unit_id, else: -portion.id
        {Integer.to_string(value), IngredientPortion.display_name(portion) || "portion"}
      end)

    portion_options ++ gram_options()
  end

  defp gram_options do
    Enum.map(Food.get_measurement_unit_by_name("gram"), fn mu ->
      {Integer.to_string(mu.id), mu.name}
    end)
  end

  # New meals open on the recipe tab; when editing, open on whichever tab has the
  # meal's content so it's visible without hunting for the right tab.
  defp initial_mode(:new, _base), do: "recipe"

  defp initial_mode(_id, base) do
    if Enum.empty?(base.recipe_user_meals) and not Enum.empty?(base.ingredient_user_meals) do
      "ingredient"
    else
      "recipe"
    end
  end

  defp init(socket, base, default_attrs) do
    changeset = UserMeal.changeset(base, default_attrs)
    existing_recipes = Ecto.Changeset.get_assoc(changeset, :recipe_user_meals)
    existing_ingredients = Ecto.Changeset.get_assoc(changeset, :ingredient_user_meals)

    # Only seed empty starter rows for a genuinely new meal (nothing on either
    # side). Keying on recipes alone would wipe an ingredient-only meal's loaded
    # ingredients when editing it.
    changeset =
      if Enum.empty?(existing_recipes) and Enum.empty?(existing_ingredients) do
        Ecto.Changeset.put_assoc(changeset, :ingredient_user_meals, [%{}])
        |> Ecto.Changeset.put_assoc(:recipe_user_meals, [%{}])
      else
        changeset
      end

    assign(socket,
      base: base,
      form: to_form(changeset),
      # Reset form for LV
      id: "form-#{System.unique_integer()}"
    )
  end

  def handle_event("submit", %{"user_meal" => user_meal_params}, socket) do
    save_user_meal(socket, socket.assigns.live_action, user_meal_params)
  end

  def handle_event("set_mode", %{"mode" => mode}, socket) do
    socket = assign(socket, :mode, mode)
    {:noreply, socket}
  end

  def handle_event("set_meal_type", %{"meal_type" => meal_type}, socket) do
    meal_type = if meal_type == "unsorted", do: nil, else: meal_type

    socket =
      update(socket, :form, fn %{source: changeset} ->
        changeset
        |> Ecto.Changeset.put_change(:meal_type, meal_type)
        |> to_form()
      end)

    {:noreply, socket}
  end

  def handle_event("new_recipe", _params, socket) do
    socket =
      update(socket, :form, fn %{source: changeset} ->
        existing = Ecto.Changeset.get_assoc(changeset, :recipe_user_meals)
        changeset = Ecto.Changeset.put_assoc(changeset, :recipe_user_meals, existing ++ [%{}])
        to_form(changeset)
      end)

    {:noreply, socket}
  end

  def handle_event("new_ingredient", _params, socket) do
    socket =
      update(socket, :form, fn %{source: changeset} ->
        existing = Ecto.Changeset.get_assoc(changeset, :ingredient_user_meals)
        changeset = Ecto.Changeset.put_assoc(changeset, :ingredient_user_meals, existing ++ [%{}])
        to_form(changeset)
      end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("validate", %{"user_meal" => user_meal_params}, socket) do
    changeset =
      Map.get(socket.assigns, :user_meal, %UserMeal{})
      |> History.change_user_meal(user_meal_params)
      |> Map.put(:action, :validate)

    socket = assign(socket, :form, to_form(changeset))

    {:noreply, assign(socket, :changeset, changeset)}
  end

  @impl true
  def handle_event("delete_ingredient_record", %{"index" => index}, socket) do
    index = String.to_integer(index)

    socket =
      update(socket, :form, fn %{source: changeset} ->
        existing = Ecto.Changeset.get_assoc(changeset, :ingredient_user_meals)
        {to_delete, rest} = List.pop_at(existing, index)

        ingredient_user_meals =
          if Ecto.Changeset.change(to_delete).data.id do
            List.replace_at(existing, index, Ecto.Changeset.change(to_delete, delete: true))
          else
            rest
          end

        changeset
        |> Ecto.Changeset.put_assoc(:ingredient_user_meals, ingredient_user_meals)
        |> to_form()
      end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("delete_recipe_record", %{"index" => index}, socket) do
    index = String.to_integer(index)

    socket =
      update(socket, :form, fn %{source: changeset} ->
        existing = Ecto.Changeset.get_assoc(changeset, :recipe_user_meals)
        {to_delete, rest} = List.pop_at(existing, index)

        recipe_user_meals =
          if Ecto.Changeset.change(to_delete).data.id do
            List.replace_at(existing, index, Ecto.Changeset.change(to_delete, delete: true))
          else
            rest
          end

        changeset
        |> Ecto.Changeset.put_assoc(:recipe_user_meals, recipe_user_meals)
        |> to_form()
      end)

    {:noreply, socket}
  end

  def get_recipe_user_meal_values(form) do
    if is_nil(form.params["recipe_user_meals"]) do
      Enum.map(form.data.recipe_user_meals, fn x -> x.recipe.id end)
    else
      form.params["recipe_user_meals"]
    end
  end

  defp save_user_meal(socket, :edit, user_meal_params) do
    case History.update_user_meal(socket.assigns.user_meal, user_meal_params) do
      {:ok, _user_meal} ->
        # Notify the parent to reload meals + close the modal via push_patch,
        # instead of push_navigate — a full remount would reset the calendar's
        # client-side accordion (JS-toggled `copen`) state.
        send(self(), {:meal_saved, %{return_to: socket.assigns.return_to, flash: "User Meal updated successfully"}})
        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  defp save_user_meal(socket, :new, user_meal_params) do
    start_dt = to_string(user_meal_params["start_dt"])

    case NaiveDateTime.from_iso8601(start_dt <> " 00:00:00") do
      {:ok, dt} ->
        user_meals_params = %{user_meal_params | "start_dt" => dt}

        case History.create_user_meal(user_meals_params) do
          {:ok, _user_meal} ->
            # See :edit above — patch back rather than remount to preserve accordion state.
            send(self(), {:meal_saved, %{return_to: socket.assigns.return_to, flash: nil}})
            {:noreply, socket}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, assign(socket, changeset: changeset)}
        end

      {:error, _reason} ->
        changeset =
          socket.assigns.user_meal
          |> History.change_user_meal(user_meal_params)
          |> Map.put(:action, :insert)
          |> Ecto.Changeset.add_error(:start_dt, "is invalid")

        {:noreply, assign(socket, changeset: changeset, form: to_form(changeset))}
    end
  end

  defp list_recipe_incomplete_user_meals(user) do
    History.list_incomplete_user_meals2(user.id, nil)
  end
end
