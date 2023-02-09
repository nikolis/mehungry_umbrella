defmodule MehungryWeb.CalendarLive.MealFormComponent do
  use MehungryWeb, :live_component

  alias Mehungry.Food
  alias Mehungry.History.UserMeal
  alias Mehungry.History
  alias Mehungry.Repo

  @impl true
  def update(%{id: id, dates: dates, current_user: user} = assigns, socket) do
    user_meal =
      case id do
        :new ->
          user_meal =
            struct(UserMeal)
            |> Repo.preload(
              recipe_user_meals: [
                recipe: [
                  recipe_ingredients: [
                    :measurement_unit,
                    ingredient: [:category, :ingredient_translation]
                  ]
                ]
              ]
            )

        id ->
          user_meal = History.get_user_meal!(id)
      end

    changeset =
      History.change_user_meal(user_meal, %{
        start_dt: dates.start,
        end_dt: dates.end,
        user_id: user.id
      })

    recipes = Food.list_recipes()
    recipe_ids = Enum.map(recipes, fn x -> x.id end)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:recipes, recipes)
     |> assign(:recipe_ids, recipe_ids)
     |> assign(:changeset, changeset)}
  end

  @impl true
  def handle_event("validate", %{"user_meal" => user_meal_params}, socket) do
    IO.inspect(user_meal_params)

    changeset =
      socket.assigns.user_meal
      |> History.change_user_meal(user_meal_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :changeset, changeset)}
  end

  def get_recipe_user_meal_values(form) do
    if(!is_nil(form.params["recipe_user_meals"])) do
      IO.inspect(form.params["recipe_user_meals"])
    else
      IO.inspect(Enum.map(form.data.recipe_user_meals, fn x -> x.recipe.id end),
        label: "Tthe within value"
      )
    end
  end

  def handle_event("save", %{"user_meal" => user_meal_params}, socket) do
    save_user_meal(socket, socket.assigns.action, user_meal_params)
  end

  defp save_user_meal(socket, :edit, user_meal_params) do
    user_meal_params = transform_rum_field(user_meal_params)

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

  defp transform_rum_field(user_meal_params) do
    user_meal_params = %{
      user_meal_params
      | "recipe_user_meals" =>
          Enum.map(user_meal_params["recipe_user_meals"], fn x -> %{"recipe_id" => x} end)
    }

    user_meal_params
  end

  defp save_user_meal(socket, :new, user_meal_params) do
    user_meal_params = transform_rum_field(user_meal_params)

    case History.create_user_meal(user_meal_params) do
      {:ok, user_meal} ->
        {:noreply,
         socket
         |> put_flash(:info, "User Meal created successfully")
         # |> push_event("create-meal", %{start: start_date, end: end_date})
         |> push_redirect(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end
end
