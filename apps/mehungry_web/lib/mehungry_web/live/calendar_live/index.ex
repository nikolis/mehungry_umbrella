defmodule MehungryWeb.CalendarLive.Index do
  use MehungryWeb, :live_view
  use MehungryWeb.Searchable, :transfers_to_search

  alias Mehungry.History.UserMeal
  alias Mehungry.Accounts
  alias Mehungry.History
  alias MehungryWeb.CalendarLive.Components
  alias Mehungry.Repo
  alias Mehungry.Food

  @impl true
  def mount(_params, session, socket) do
    user = Accounts.get_user_by_session_token(session["user_token"])
    user_meals = History.list_history_user_meals_for_user(user.id)
    recipes = list_recipes(user)

    user_meals =
      Enum.map(user_meals, fn x ->
        %{
          id: x.id,
          start: x.start_dt,
          end: x.end_dt,
          title: x.title,
          sub_title:
            Enum.reduce(x.recipe_user_meals, "", fn x, acc ->
              case String.length(acc) do
                0 ->
                  x.recipe.title

                _ ->
                  acc <> ", " <> x.recipe.title
              end
            end)
        }
      end)

    socket = push_event(socket, "create_meals", %{meals: user_meals})

    {
      :ok,
      socket
      |> assign(:user, user)
      |> assign(:recipes, recipes)
      # |> push_event("create_meals", user_meals)
    }
  end

  defp apply_action(socket, :index, _params) do
    socket
  end

  defp apply_action(socket, :edit, %{"id" => id} = _params) do
    user_meal = History.get_user_meal!(id)

    # user_meal = %UserMeal{user_meal| recipe_user_meals: Enum.map(user_meal.recipe_user_meals, fn x -> x.recipe_id end) }
    socket =
      socket
      |> assign(:page_title, "Edit Meal")
      |> assign(:user_meal, user_meal)
      |> assign(:dates, %{start: user_meal.start_dt, end: user_meal.end_dt})

    socket
  end

  defp apply_action(socket, :new, %{"start" => start_date, "end" => end_date} = _params) do
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

    changeset =
      History.change_user_meal(user_meal, %{
        start_dt: start_date,
        end_dt: end_date,
        user_id: socket.assigns.user.id
      })

    socket
    |> assign(:page_title, "Create Meal")
    |> assign(:user_meal, user_meal)
    |> assign(
      :dates,
      %{start: start_date, end: end_date}
    )
    |> assign(:changeset, changeset)
    |> assign(:recipes, list_recipes(nil))
  end

  @impl true
  def handle_params(params, _url, socket) do
    socket =
      assign(
        socket,
        :invocations,
        case Map.get(socket.assigns, :invocations) do
          nil ->
            1

          x ->
            x + 1
        end
      )

    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  @impl true
  def handle_event("initial_modal", %{"start" => start_date, "end" => end_date}, socket) do
    {:noreply, push_patch(socket, to: "/calendar/#{start_date}/#{end_date}", replace: true)}
  end

  def handle_event("delete_user_meal", %{"id" => meal_id}, socket) do
    user_meal = History.get_user_meal!(meal_id)

    case History.delete_user_meal(user_meal) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "User Meal Deleted")
         |> push_redirect(to: Routes.calendar_index_path(socket, :index))}

      {:error, changeset} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("close-modal", _, socket) do
    {:noreply, push_patch(socket, to: "/calendar/", replace: true)}
  end

  @impl true
  def handle_event("edit_modal", %{"id" => id}, socket) do
    {:noreply, push_patch(socket, to: "/calendar/#{id}", replace: true)}
  end

  defp list_recipes(user) do
    Food.list_user_recipes_for_selection(user)
  end
end
