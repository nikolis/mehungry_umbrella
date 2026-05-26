defmodule MehungryWeb.CalendarLive.Index do
  use MehungryWeb, :live_view
  use MehungryWeb.Searchable, :transfers_to_search
  use ViewportHelpers
  use MehungryWeb.Presence, :user_tracking

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
    user_meals = load_and_format_user_meals(user.id)
    recipes = list_recipes(user)
    socket = assign_device_kind(socket)
    socket = push_event(socket, "create_meals", %{meals: user_meals})

    {
      :ok,
      socket
      |> assign(:user, user)
      |> assign(:child_ids, [])
      |> assign(:calendar_view, "week_view")
      |> assign(:particular_date, nil)
      |> assign(:page_title, "Meal planner")
      |> assign(:user_meals, user_meals)
      |> assign(:recipes, recipes)
      |> assign(:detail_return_to, nil)
      |> assign(:ai_plan_generating, false)
      |> assign(:ai_plan_task_ref, nil)
      |> assign(:ai_plan_result, nil)
      |> assign(:ai_quota_exceeded, false)
      |> assign(:show_ai_panel, false)
    }
  end

  defp apply_action(socket, :index, _params) do
    maybe_track_user(%{}, socket)
    socket
  end

  defp apply_action(socket, :particular, %{"date" => date} = _params) do
    maybe_track_user(%{}, socket)

    socket = push_event(socket, "go_to_date", %{date: date})

    socket
    |> assign(:detail_return_to, ~p"/calendar/ondate/#{date}")
    |> assign(:particular_date, date)
  end

  defp apply_action(socket, :nutrition_details, %{"date" => date} = _params) do
    maybe_track_user(%{}, socket)

    socket
    |> assign(:nutrition_details, date)
  end

  defp apply_action(socket, :edit, %{"id" => id} = _params) do
    maybe_track_user(%{}, socket)

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
    maybe_track_user(%{}, socket)

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
        ],
        ingredient_user_meals: [:ingredient, :measurement_unit]
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
  def handle_params(params, uri, socket) do
    socket = assign(socket, :path, uri)

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
  def handle_info({ref, result}, socket) when is_reference(ref) do
    Process.demonitor(ref, [:flush])

    if socket.assigns.ai_plan_task_ref == ref do
      case result do
        {:ok, created, skipped} ->
          Mehungry.Subscriptions.record_usage(socket.assigns.user.id, "meal_plan")
          user_meals = load_and_format_user_meals(socket.assigns.user.id)
          result_msg = build_result_message(length(created), skipped)

          {:noreply,
           socket
           |> assign(:ai_plan_generating, false)
           |> assign(:ai_plan_task_ref, nil)
           |> assign(:ai_plan_result, result_msg)
           |> assign(:user_meals, user_meals)
           |> push_event("create_meals", %{meals: user_meals})}

        {:error, reason} ->
          {:noreply,
           socket
           |> assign(:ai_plan_generating, false)
           |> assign(:ai_plan_task_ref, nil)
           |> put_flash(:error, "Could not generate plan: #{reason}")}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _, _reason}, socket) when is_reference(ref) do
    if socket.assigns.ai_plan_task_ref == ref do
      {:noreply,
       socket
       |> assign(:ai_plan_generating, false)
       |> assign(:ai_plan_task_ref, nil)
       |> put_flash(:error, "AI plan generation failed unexpectedly")}
    else
      {:noreply, socket}
    end
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
  def handle_event("resize_chart", %{"width" => width}, socket) do
    for child_id <- socket.assigns.child_ids do
      send_update(MehungryWeb.CalendarLive.Calendar.PieChart, resize: width)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("date-details", %{"date" => start_date}, socket) do
    {:noreply, push_patch(socket, to: "/calendar/details/#{start_date}", replace: true)}
  end

  def handle_event("toggle_ai_panel", _, socket) do
    {:noreply, assign(socket, :show_ai_panel, !socket.assigns.show_ai_panel)}
  end

  def handle_event("ai_plan_week", %{"prompt" => prompt}, socket) when prompt != "" do
    user = socket.assigns.user

    case Mehungry.Subscriptions.check_quota(user.id, "meal_plan") do
      :ok ->
        recipes = socket.assigns.recipes
        start_date = Date.utc_today()

        task =
          Task.async(fn ->
            Mehungry.AI.MealPlanGenerator.run(prompt, recipes, start_date, user.id)
          end)

        {:noreply,
         socket
         |> assign(:ai_plan_generating, true)
         |> assign(:ai_plan_task_ref, task.ref)
         |> assign(:ai_plan_result, nil)
         |> assign(:ai_quota_exceeded, false)}

      {:error, :quota_exceeded} ->
        {:noreply, assign(socket, :ai_quota_exceeded, true)}
    end
  end

  def handle_event("ai_plan_week", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("toggle_basket", %{"view" => view}, socket) do
    socket =
      case view do
        "week_view" ->
          assign(socket, :calendar_view, "week_view")

        "day_view" ->
          assign(socket, :calendar_view, "day_view")
      end

    {:noreply, socket}
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

  defp load_and_format_user_meals(user_id) do
    History.list_history_user_meals_for_user(user_id)
    |> Enum.map(fn x ->
      %{
        id: x.id,
        start_dt: x.start_dt,
        end: x.end_dt,
        title: x.title,
        ingredient_user_meals:
          Enum.map(x.ingredient_user_meals, fn y ->
            %{
              title: y.ingredient.name,
              portions: y.quantity,
              measurement_unit: y.measurement_unit.name,
              primary_size: 6,
              img_url: nil,
              recipe: %{
                id: y.ingredient.id,
                nutrients:
                  Enum.map(y.ingredient.ingredient_nutrients, fn n ->
                    %{
                      amount: n.amount,
                      name: n.nutrient.name,
                      measurement_unit: %{name: n.nutrient.measurement_unit.name}
                    }
                  end),
                primary_size: 5
              }
            }
          end),
        recipe_user_meals:
          Enum.map(x.recipe_user_meals, fn y ->
            %{
              title: y.recipe.title,
              consume_portions: y.consume_portions,
              cooking_portions: y.cooking_portions,
              servings: y.recipe.servings,
              recipe_nutrients: y.recipe.nutrients,
              img_url: y.recipe.image_url,
              primary_size: y.recipe.primary_nutrients_size,
              recipe_id: y.recipe.id
            }
          end)
      }
    end)
  end

  defp build_result_message(created, 0),
    do: "Added #{created} meals to your calendar."

  defp build_result_message(created, skipped),
    do: "Added #{created} meals to your calendar (#{skipped} skipped due to errors)."
end
