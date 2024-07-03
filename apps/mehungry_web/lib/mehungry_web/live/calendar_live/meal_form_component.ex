defmodule MehungryWeb.CalendarLive.MealFormComponent do
  use MehungryWeb, :live_component

  import MehungryWeb.CoreComponents

  alias Mehungry.History.UserMeal

  alias Mehungry.Food
  alias Mehungry.History
  alias MehungryWeb.CalendarLive.Components

  def is_empty(%Phoenix.HTML.Form{} = form, atom_key) do
    key_form_params = form.params[Atom.to_string(atom_key)]
    key_changeset = form.source.changes[atom_key]
    key_form_data = Map.from_struct(form.data)[atom_key]

    if is_nil(key_form_data) and is_nil(key_changeset) and is_nil(key_form_params) do
      false
    else
      false
    end
  end

  def has_content(_form, _atom_key) do
    "input_with_content"
  end

  @impl true
  def update(%{id: id, dates: dates, current_user: user} = assigns, socket) do
    default_attrs = %{
      start_dt: dates.start,
      end_dt: dates.end,
      user_id: user.id
    }

    base_user_meal =
      case id do
        :new ->
          struct(UserMeal)

        # |> Repo.preload(:recipe_user_meals, :consume_recipe_user_meals)

        id ->
          History.get_user_meal_raw!(id)
      end

    recipes = Food.list_user_recipes_for_selection(assigns.current_user)
    incomplete_user_meals = list_recipe_incomplete_user_meals(assigns.current_user)

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
      |> assign(:user_meal, base_user_meal)
      |> assign(:recipe_ids, recipe_ids)

    {:ok, init(socket, base_user_meal, default_attrs)}
  end

  defp init(socket, base, default_attrs) do
    changeset = UserMeal.changeset(base, default_attrs)

    assign(socket,
      base: base,
      form: to_form(changeset),
      # Reset form for LV
      id: "form-#{System.unique_integer()}"
    )
  end

  def is_open(action, invocations) do
    case action do
      :new ->
        "is-open"

      :edit ->
        "is-open"

      _ ->
        if invocations > 1 do
          "is-closing"
        else
          "is-closed"
        end
    end
  end

  def get_not_nil(first, second) do
    if(first) do
      first
    else
      second
    end
  end

  def handle_event("submit", %{"user_meal" => user_meal_params}, socket) do
    save_user_meal(socket, socket.assigns.live_action, user_meal_params)
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

  def handle_event("new_recipe", _params, socket) do
    socket =
      update(socket, :form, fn %{source: changeset} ->
        existing = Ecto.Changeset.get_assoc(changeset, :recipe_user_meals)
        changeset = Ecto.Changeset.put_assoc(changeset, :recipe_user_meals, existing ++ [%{}])
        to_form(changeset)
      end)

    {:noreply, socket}
  end

  def handle_event("new_consume_recipe", _params, socket) do
    socket =
      update(socket, :form, fn %{source: changeset, params: _params} ->
        existing = Ecto.Changeset.get_assoc(changeset, :consume_recipe_user_meals)

        changeset =
          Ecto.Changeset.put_assoc(changeset, :consume_recipe_user_meals, existing ++ [%{}])

        to_form(changeset)
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

  @impl true
  def handle_event("delete_recipe_consume_record", %{"index" => index}, socket) do
    index = String.to_integer(index)

    socket =
      update(socket, :form, fn %{source: changeset} ->
        existing = Ecto.Changeset.get_assoc(changeset, :consume_recipe_user_meals)
        {to_delete, rest} = List.pop_at(existing, index)

        consume_recipe_user_meals =
          if Ecto.Changeset.change(to_delete).data.id do
            List.replace_at(existing, index, Ecto.Changeset.change(to_delete, delete: true))
          else
            rest
          end

        changeset
        |> Ecto.Changeset.put_assoc(:consume_recipe_user_meals, consume_recipe_user_meals)
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
    IO.inspect(socket.assigns.return_to, label: "new yuser meal;234")

    case History.update_user_meal(socket.assigns.user_meal, user_meal_params) do
      {:ok, _user_meal} ->
        {:noreply,
         socket
         |> put_flash(:info, "User Meal updated successfully")
         |> push_redirect(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  defp save_user_meal(socket, :new, user_meal_params) do
    IO.inspect(socket.assigns.return_to, label: "new yuser meal;")
    IO.inspect(user_meal_params)

    case History.create_user_meal(user_meal_params) do
      {:ok, user_meal} ->
        date = NaiveDateTime.to_string(user_meal.start_dt)

        IO.inspect(date,
          label:
            "Date adsoaifds--------------------------------------------------------------------------------------------------"
        )

        {:noreply,
         socket
         |> put_flash(:info, "User Meal created successfully")
         |> push_redirect(to: "/calendar/ondate/" <> date)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  defp list_recipe_incomplete_user_meals(user) do
    History.list_incomplete_user_meals2(user.id, nil)
  end
end
