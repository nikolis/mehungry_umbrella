defmodule MehungryWeb.CalendarLive.Index do
  use MehungryWeb, :live_view

  import Ecto

  alias Mehungry.Repo
  alias Mehungry.Food
  alias Mehungry.Food.Recipe
  alias Mehungry.History.UserMeal
  alias Mehungry.Accounts
  alias Mehungry.History

  @impl true
  def mount(_params, session, socket) do
    user = Accounts.get_user_by_session_token(session["user_token"])
    user_meals = History.list_history_user_meals_for_user(user.id)

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
      # |> push_event("create_meals", user_meals)
    }
  end

  defp apply_action(socket, :index, _params) do
    socket
  end

  defp apply_action(socket, :edit, %{"id" => id} = params) do
    user_meal = History.get_user_meal!(id)
    IO.inspect(user_meal, label: "The user meal")

    # user_meal = %UserMeal{user_meal| recipe_user_meals: Enum.map(user_meal.recipe_user_meals, fn x -> x.recipe_id end) }
    socket =
      socket
      |> assign(:page_title, "Edit Meal")
      |> assign(:user_meal, user_meal)
      |> assign(:dates, %{start: user_meal.start_dt, end: user_meal.end_dt})

    socket
  end

  defp apply_action(socket, :new, %{"start" => start_date, "end" => end_date} = params) do
    socket =
      socket
      |> assign(:page_title, "Create Meal")
      |> assign(:user_meal, %UserMeal{})
      |> assign(:dates, %{start: start_date, end: end_date})

    socket
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  @impl true
  def handle_event("initial_modal", %{"start" => start_date, "end" => end_date}, socket) do
    {:noreply, push_patch(socket, to: "/calendar/#{start_date}/#{end_date}", replace: true)}
  end

  @impl true
  def handle_event("edit_modal", %{"id" => id}, socket) do
    {:noreply, push_patch(socket, to: "/calendar/#{id}", replace: true)}
  end
end