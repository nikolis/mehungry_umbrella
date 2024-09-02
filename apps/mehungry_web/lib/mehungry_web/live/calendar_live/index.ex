defmodule MehungryWeb.CalendarLive.Index do
  use MehungryWeb, :live_view
  use MehungryWeb.Searchable, :transfers_to_search
  use ViewportHelpers

  import MehungryWeb.CoreComponents

  alias Mehungry.History.UserMeal
  alias Mehungry.Accounts
  alias Mehungry.History
  alias Mehungry.Repo
  alias Mehungry.Food

  # https://gist.github.com/cblavier/0e227de6fd1dfa00814b88642cdcb2a9
  # def render(assigns) do
  #  render_for_device(SomeView, "show.html", assigns)
  # end

  def mount_search(_params, session, socket) do
    user = Accounts.get_user_by_session_token(session["user_token"])
    user_meals = History.list_history_user_meals_for_user(user.id)
    recipes = list_recipes(user)
    socket = assign_device_kind(socket)

    user_meals =
      Enum.map(user_meals, fn x ->
        %{
          id: x.id,
          start_dt: x.start_dt,
          end: x.end_dt,
          title: x.title,
          recipe_user_meals: Enum.map(x.recipe_user_meals, fn y -> %{title: y.recipe.title} end)
        }
      end)

    socket = push_event(socket, "create_meals", %{meals: user_meals})

    {
      :ok,
      socket
      |> assign(:user, user)
      |> assign(:particular_date, nil)
      |> assign(:user_meals, user_meals)
      |> assign(:recipes, recipes)
      |> assign(:detail_return_to, nil)
    }
  end

  defp apply_action(socket, :index, _params) do
    socket
  end

  defp apply_action(socket, :particular, %{"date" => date} = _params) do
    socket = push_event(socket, "go_to_date", %{date: date})

    socket
    |> assign(:detail_return_to, ~p"/calendar/ondate/#{date}")
    |> assign(:particular_date, date)
  end

  defp apply_action(socket, :nutrition_details, %{"date" => date} = _params) do
    socket
    |> assign(:nutrition_details, date)
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

  defp apply_action(socket, :new, %{"start" => start_date, "title" => title} = _params) do
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
        title: title,
        user_id: socket.assigns.user.id
      })

    socket
    |> assign(:page_title, "Create Meal")
    |> assign(:user_meal, user_meal)
    |> assign(
      :dates,
      %{start: start_date}
    )
    |> assign(:title, title)
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
  def handle_info({:initial_modal, %{"date" => start_date, "title" => title}}, socket) do
    {:noreply, push_patch(socket, to: "/calendar/#{start_date}/#{title}", replace: true)}
  end

  @impl true
  def handle_info({:particular_date, %{"date" => start_date}}, socket) do
    {:noreply, push_patch(socket, to: "/calendar/ondate/#{start_date}", replace: true)}
  end

  @impl true
  def handle_event("date-details", %{"date" => start_date}, socket) do
    {:noreply, push_patch(socket, to: "/calendar/details/#{start_date}", replace: true)}
  end

  def handle_event("delete_user_meal", %{"id" => meal_id}, socket) do
    user_meal = History.get_user_meal!(meal_id)

    case History.delete_user_meal(user_meal) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "User Meal Deleted")
         |> push_navigate(to: Routes.calendar_index_path(socket, :index))}

      {:error, _changeset} ->
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
