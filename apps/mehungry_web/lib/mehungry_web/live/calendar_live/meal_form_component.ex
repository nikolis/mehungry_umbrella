defmodule MehungryWeb.CalendarLive.MealFormComponent do
  use MehungryWeb, :live_component

  import MehungryWeb.CoreComponents

  alias Mehungry.History.UserMeal

  alias Mehungry.Food
  alias Mehungry.History
  alias MehungryWeb.CalendarLive.Components

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
          History.get_user_meal_raw!(user.id, id)
      end

    recipes = Food.list_user_recipes_for_selection(assigns.current_user)
    incomplete_user_meals = list_recipe_incomplete_user_meals(assigns.current_user)
    # Fetch the gram measurement units once here rather than per ingredient row on
    # every render/validate (the old `get_measurement_units/2` ran this query N times).
    measurement_units = Food.get_measurement_unit_by_name("gram")

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
      |> assign(:measurement_units, measurement_units)
      |> assign(:user_meal, base_user_meal)
      |> assign(:recipe_ids, recipe_ids)
      |> assign(:mode, initial_mode(id, base_user_meal))

    {:ok, init(socket, base_user_meal, default_attrs)}
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
