defmodule MehungryWeb.CalendarLive.Index do
  use MehungryWeb, :live_view
  use ViewportHelpers
  use MehungryWeb.Presence, :user_tracking
  use MehungryWeb.LiveHelpers, :hook_for_update_recipe_details_component

  import MehungryWeb.CoreComponents

  alias Mehungry.History.UserMeal
  alias Mehungry.Accounts
  alias Mehungry.History
  alias Mehungry.Professionals
  alias Mehungry.Repo
  alias Mehungry.Food
  alias Mehungry.Users
  alias MehungryWeb.RecipeFlags

  # https://gist.github.com/cblavier/0e227de6fd1dfa00814b88642cdcb2a9
  # def render(assigns) do
  #  render_for_device(SomeView, "show.html", assigns)
  # end

  @impl true
  def mount(_params, session, socket) do
    user = Accounts.get_user_by_session_token(session["user_token"])

    profile = Accounts.get_user_profile_by_user_id(user.id)
    condition_ids = RecipeFlags.opted_in_condition_ids(profile)
    calorie_target = profile && profile.daily_calorie_target

    user_meals = load_and_format_user_meals(user.id)
    recipes = list_recipes(user)
    socket = assign_device_kind(socket)
    socket = push_event(socket, "create_meals", %{meals: user_meals})

    {
      :ok,
      socket
      |> assign(:user, user)
      |> assign(:condition_ids, condition_ids)
      |> assign(:calorie_target, calorie_target)
      |> assign(:calendar_view, "week_view")
      |> assign(:particular_date, nil)
      |> assign(:page_title, "Meal planner")
      |> assign(:user_meals, user_meals)
      |> assign(:recipes, recipes)
      |> assign(:detail_return_to, nil)
      |> assign(:ai_plan_generating, false)
      |> assign(:ai_plan_task_ref, nil)
      |> assign(:ai_plan_result, nil)
      |> assign(
        :ai_quota_exceeded,
        Mehungry.Subscriptions.check_quota(user.id, "meal_plan") == {:error, :quota_exceeded}
      )
      |> assign(:has_nutritionist, not is_nil(Professionals.get_assignment_for_client(user.id)))
      |> assign(:week_rating, nil)
      # Assigns the recipe-details modal (RecipeDetailsComponent via the shared
      # LiveHelpers hook) reads for save/follow toggles.
      |> assign(:recipe, nil)
      |> assign(:current_user_recipes, Users.list_user_saved_recipe_ids(user))
      |> assign(
        :current_user_follows,
        user |> Users.list_user_follows() |> Enum.map(& &1.follow_id)
      )
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

  defp apply_action(socket, :show_recipe, %{"recipe_id" => recipe_id} = _params) do
    maybe_track_user(%{}, socket)

    recipe = Food.get_recipe!(String.to_integer(recipe_id), socket.assigns.current_language)

    Mehungry.Posts.subscribe_to_recipe(%{recipe_id: recipe.id})

    socket
    |> assign(:page_title, recipe.title)
    |> assign(:recipe, recipe)
  end

  defp apply_action(socket, :edit, %{"id" => id} = _params) do
    maybe_track_user(%{}, socket)

    user_meal = History.get_user_meal!(socket.assigns.user.id, id)

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
  def handle_info({:meal_saved, %{return_to: return_to, flash: flash}}, socket) do
    user_meals = load_and_format_user_meals(socket.assigns.user.id)

    socket =
      socket
      |> assign(:user_meals, user_meals)
      |> push_event("create_meals", %{meals: user_meals})

    socket = if flash, do: put_flash(socket, :info, flash), else: socket

    {:noreply, push_patch(socket, to: return_to, replace: true)}
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
  # The VegaLite JS hook fires this on window resize. Pie charts render at a
  # fixed size, so there's nothing to recompute — just acknowledge it.
  def handle_event("resize_chart", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("date-details", %{"date" => start_date}, socket) do
    {:noreply, push_patch(socket, to: "/calendar/details/#{start_date}", replace: true)}
  end

  @impl true
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

  @impl true
  def handle_event("toggle_basket", %{"view" => view}, socket) do
    socket =
      case view do
        "day_view" ->
          assign(socket, :calendar_view, "day_view")

        _ ->
          assign(socket, :calendar_view, "week_view")
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("delete_user_meal", %{"id" => meal_id}, socket) do
    user_meal = History.get_user_meal!(socket.assigns.user.id, meal_id)

    case History.delete_user_meal(user_meal) do
      {:ok, _} ->
        # Patch back rather than push_navigate so the calendar's client-side
        # accordion (JS-toggled `copen`) state survives the delete.
        user_meals = load_and_format_user_meals(socket.assigns.user.id)

        {:noreply,
         socket
         |> assign(:user_meals, user_meals)
         |> push_event("create_meals", %{meals: user_meals})
         |> put_flash(:info, "User Meal Deleted")
         |> push_patch(to: ~p"/calendar", replace: true)}

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

  @impl true
  def handle_event("show_recipe_details", %{"recipe_id" => recipe_id}, socket) do
    {:noreply, push_patch(socket, to: ~p"/calendar/recipe/#{recipe_id}", replace: true)}
  end

  @impl true
  def handle_event(
        "rate_meal_plan",
        %{"score" => score, "date" => date_str, "type" => type} = params,
        socket
      ) do
    user_id = socket.assigns.user.id
    comment = Map.get(params, "comment", nil)

    with {:ok, date} <- Date.from_iso8601(date_str),
         {parsed_score, ""} <- Integer.parse(score) do
      attrs = %{
        user_id: user_id,
        rating_type: type,
        score: parsed_score,
        comment: comment,
        rated_for_date: date
      }

      case Professionals.upsert_meal_plan_rating(attrs) do
        {:ok, _rating} ->
          {:noreply, put_flash(socket, :info, "Rating saved!")}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Could not save rating.")}
      end
    else
      _ ->
        {:noreply, put_flash(socket, :error, "Could not save rating.")}
    end
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
        meal_type: x.meal_type,
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
