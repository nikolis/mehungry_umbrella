defmodule MehungryWeb.CalendarLive.Index do
  use MehungryWeb, :live_view
  use ViewportHelpers
  use MehungryWeb.Presence, :user_tracking
  use MehungryWeb.LiveHelpers, :hook_for_update_recipe_details_component

  import MehungryWeb.CoreComponents

  alias Mehungry.Accounts
  alias Mehungry.History
  alias Mehungry.Professionals
  alias Mehungry.Food
  alias Mehungry.Users
  alias Mehungry.AI.Agents.MealPlanAgent

  # https://gist.github.com/cblavier/0e227de6fd1dfa00814b88642cdcb2a9
  # def render(assigns) do
  #  render_for_device(SomeView, "show.html", assigns)
  # end

  @impl true
  def mount(_params, session, socket) do
    user = Accounts.get_user_by_session_token(session["user_token"])

    profile = Accounts.get_user_profile_by_user_id(user.id)
    calorie_target = profile && profile.daily_calorie_target

    # Personal "foods I avoid" list: the raw list (for the editor) + the
    # normalized terms (reusing the meal-plan enforcement engine) the calendar
    # uses to flag logged meals that contain one.
    avoid_foods = (profile && profile.avoid_foods) || []
    avoid_terms = MealPlanAgent.avoid_terms(%{avoid_foods: avoid_foods})

    socket =
      socket
      |> assign_device_kind()
      |> assign(:user, user)
      |> assign(:user_profile, profile)
      |> assign(:calorie_target, calorie_target)
      |> assign(:avoid_foods, avoid_foods)
      |> assign(:avoid_terms, avoid_terms)
      |> assign(:calendar_view, "week_view")
      |> assign(:particular_date, nil)
      |> assign(:page_title, "Meal planner")
      |> assign(:detail_return_to, nil)
      |> assign(:ai_plan_generating, false)
      |> assign(:ai_plan_task_ref, nil)
      |> assign(:ai_plan_result, nil)
      |> assign(:share_generating, false)
      |> assign(:share_posted, false)
      |> assign(:share_regenerate, false)
      |> assign(:blueprint_progress, nil)
      |> assign(:week_rating, nil)
      # Assigns the recipe-details modal (RecipeDetailsComponent via the shared
      # LiveHelpers hook) reads for save/follow toggles.
      |> assign(:recipe, nil)
      # Heavy per-user data (meals, blueprints, saved/follows, quota, share card)
      # is loaded once the socket connects — this is a private, noindex, JS-hydrated
      # page the user always upgrades to WS, so the disconnected render's queries
      # would be wasted DB-pool load. Safe empty defaults keep the first paint valid.
      # See docs/implementation/liveview_optimization_plan.md.
      |> assign(:user_meals, [])
      |> assign(:day_notes, %{})
      |> assign(:recipes, [])
      |> assign(:blueprints, [])
      |> assign(:preselected_blueprint_id, nil)
      |> assign(:active_blueprint, nil)
      |> assign(:share_graphic, nil)
      |> assign(:ai_quota_exceeded, false)
      |> assign(:has_nutritionist, false)
      |> assign(:current_user_recipes, [])
      |> assign(:current_user_follows, [])

    socket = if connected?(socket), do: load_calendar_data(socket), else: socket

    {:ok, socket}
  end

  # Loads the calendar's per-user data on the connected mount (see mount/3).
  defp load_calendar_data(socket) do
    user = socket.assigns.user
    profile = socket.assigns.user_profile
    user_meals = load_and_format_user_meals(user.id, Date.utc_today(), current_language(socket))

    # The blueprint the user was following persists on their profile, so the
    # calendar re-opens "following" it until they switch or stop.
    followed_blueprint = load_selected_blueprint(user.id, profile && profile.followed_blueprint_id)
    blueprints = load_calendar_blueprints(user.id) |> prepend_blueprint(followed_blueprint)

    socket
    |> assign(:user_meals, user_meals)
    |> assign(:day_notes, day_notes_for(user.id, Date.utc_today()))
    |> assign(:recipes, list_recipes(user))
    |> assign(:blueprints, blueprints)
    |> assign(:preselected_blueprint_id, followed_blueprint && to_string(followed_blueprint.id))
    |> assign(:active_blueprint, followed_blueprint)
    |> assign_latest_share_graphic()
    |> assign(
      :ai_quota_exceeded,
      Mehungry.Subscriptions.check_quota(user.id, "meal_plan") == {:error, :quota_exceeded}
    )
    |> assign(:has_nutritionist, not is_nil(Professionals.get_assignment_for_client(user.id)))
    |> assign(:current_user_recipes, Users.list_user_saved_recipe_ids(user))
    |> assign(
      :current_user_follows,
      user |> Users.list_user_follows() |> Enum.map(& &1.follow_id)
    )
    |> push_event("create_meals", %{meals: user_meals})
  end

  defp apply_action(socket, :index, params) do
    maybe_track_user(%{}, socket)

    # `:index` does not reset `@particular_date`, so `current_calendar_date/1`
    # keeps the viewed week when patching back to `/calendar` (close-modal,
    # delete, stop-following) rather than snapping to today.
    socket
    |> maybe_preselect_blueprint(params["blueprint_id"])
    |> reload_week_meals()
    |> assign_blueprint_progress()
  end

  defp apply_action(socket, :particular, %{"date" => date} = _params) do
    maybe_track_user(%{}, socket)

    socket = push_event(socket, "go_to_date", %{date: date})

    # Week navigation reaches here via a `push_patch` with no DB reload of its
    # own, so load the newly-viewed week's meals here.
    socket
    |> assign(:detail_return_to, ~p"/calendar/ondate/#{date}")
    |> assign(:particular_date, date)
    |> reload_week_meals()
    |> assign_blueprint_progress()
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

    user_meal = History.blank_user_meal()

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

          user_meals =
            load_and_format_user_meals(
            socket.assigns.user.id,
            current_calendar_date(socket),
            current_language(socket)
          )
          result_msg = build_result_message(length(created), skipped)

          {:noreply,
           socket
           |> assign(:ai_plan_generating, false)
           |> assign(:ai_plan_task_ref, nil)
           |> assign(:ai_plan_result, result_msg)
           |> assign(:user_meals, user_meals)
           |> assign_blueprint_progress()
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
    user_meals =
      load_and_format_user_meals(
            socket.assigns.user.id,
            current_calendar_date(socket),
            current_language(socket)
          )

    socket =
      socket
      |> assign(:user_meals, user_meals)
      |> assign_blueprint_progress()
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

  # Private per-day journal note (symptoms / how I felt / energy). Condition-
  # agnostic and never leaves the calendar; a blank body clears the note.
  @impl true
  def handle_event("save_day_note", %{"date" => date_str, "body" => body}, socket) do
    with {:ok, date} <- Date.from_iso8601(date_str),
         {:ok, _} <- Mehungry.History.upsert_day_note(socket.assigns.user.id, date, body) do
      {:noreply,
       socket
       |> assign(:day_notes, day_notes_for(socket.assigns.user.id, current_calendar_date(socket)))
       |> put_flash(:info, "Note saved")}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not save note")}
    end
  end

  # Personal "foods I avoid" list. Newline/comma-separated textarea → a cleaned
  # list on the user's profile; the calendar then flags any logged food whose
  # name contains one. Not gated behind a nutritionist blueprint.
  @impl true
  def handle_event("save_avoid_foods", %{"foods" => raw}, socket) do
    user = socket.assigns.user

    profile =
      socket.assigns[:user_profile] || Accounts.create_user_profile_if_needed(user)

    case Accounts.set_avoid_foods(profile, raw) do
      {:ok, updated} ->
        avoid_terms = MealPlanAgent.avoid_terms(%{avoid_foods: updated.avoid_foods})

        {:noreply,
         socket
         |> assign(:user_profile, updated)
         |> assign(:avoid_foods, updated.avoid_foods)
         |> assign(:avoid_terms, avoid_terms)
         |> put_flash(:info, "Avoid list saved")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not save your avoid list")}
    end
  end

  @impl true
  def handle_event("ai_plan_week", %{"prompt" => prompt} = params, socket) when prompt != "" do
    user = socket.assigns.user

    case Mehungry.Subscriptions.check_quota(user.id, "meal_plan") do
      :ok ->
        recipes = socket.assigns.recipes
        # Anchor the generated 7-day plan to the Monday of the week currently in
        # view — the same framing the calendar grid (Widget `beginning_of_week`)
        # and the blueprint-progress panel (`assign_blueprint_progress`) use. Laying
        # the plan from `Date.utc_today()` instead straddled two display weeks when
        # generating mid-week, so the just-generated plan filled only part of the
        # visible grid and the progress panel read half-empty.
        start_date = Date.beginning_of_week(current_calendar_date(socket))
        # Optional blueprint to constrain generation. Loaded (owner-scoped) and
        # threaded through now; the generator treats it as an inert hint until
        # blueprint-aware planning lands.
        blueprint = load_selected_blueprint(user.id, params["blueprint_id"])

        task =
          Task.async(fn ->
            Mehungry.AI.MealPlanGenerator.run(prompt, recipes, start_date, user.id, blueprint)
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

  # ── Weekly-plan share card ──────────────────────────────────────────────────
  # Renders the viewed week into a shareable card off the viewed `@user_meals`
  # (the exact data the grid shows), so the card never re-queries or re-derives.
  @impl true
  def handle_event("generate_week_card", params, socket) do
    user = socket.assigns.user
    week_start = Date.beginning_of_week(current_calendar_date(socket))
    meals = socket.assigns.user_meals
    goal = params |> Map.get("goal_label", "") |> String.trim()
    goal = if goal == "", do: nil, else: goal
    locale = Map.get(socket.assigns, :current_language, "en")

    {:noreply,
     socket
     |> assign(:share_generating, true)
     |> assign(:share_graphic, nil)
     |> assign(:share_posted, false)
     |> start_async(:generate_week_card, fn ->
       MehungryWeb.WeeklyPlanGraphicGenerator.generate(user, week_start, meals,
         goal_label: goal,
         locale: locale
       )
     end)}
  end

  @impl true
  def handle_event("post_week_plan", _params, socket) do
    case socket.assigns.share_graphic do
      %{} = graphic ->
        title = MehungryWeb.WeeklyPlanGraphicGenerator.post_title(graphic)

        # Also publish the week as a full, crawlable plan snapshot so the feed
        # post opens the day-by-day `/meal-plans/:slug` details page (not just the
        # card photo). If publishing fails, the post still goes out with the photo.
        published_meal_plan_id =
          case Mehungry.PublishedPlans.publish_week(socket.assigns.user, graphic.week_start,
                 title: title,
                 goal_label: graphic.goal_label,
                 locale: graphic.locale,
                 og_image_url: graphic.image_url
               ) do
            {:ok, plan} -> plan.id
            _ -> nil
          end

        case Mehungry.Posts.create_weekly_plan_post(graphic, title,
               published_meal_plan_id: published_meal_plan_id
             ) do
          {:ok, _post} ->
            {:noreply,
             socket
             |> assign(:share_posted, true)
             |> put_flash(:info, "Your weekly plan was posted to the feed.")}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Could not post your weekly plan.")}
        end

      _ ->
        {:noreply, socket}
    end
  end

  # "Re-generate" from the existing-card view: reveal the form again so the user
  # can (optionally change the goal and) replace the saved card.
  @impl true
  def handle_event("start_regenerate", _params, socket) do
    {:noreply, assign(socket, :share_regenerate, true)}
  end

  # Modal close: drop the transient flags and re-show the saved card for the week
  # (so reopening shows the last generated card, not a blank form).
  @impl true
  def handle_event("reset_share", _params, socket) do
    {:noreply,
     socket
     |> assign(:share_generating, false)
     |> assign(:share_posted, false)
     |> assign(:share_regenerate, false)
     |> assign_latest_share_graphic()}
  end

  @impl true
  def handle_event("stop_following_blueprint", _params, socket) do
    {:noreply,
     socket
     |> persist_followed_blueprint(nil)
     |> assign(:active_blueprint, nil)
     |> assign(:blueprint_progress, nil)
     |> assign(:preselected_blueprint_id, nil)
     |> push_patch(to: ~p"/calendar", replace: true)}
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
        user_meals =
          load_and_format_user_meals(
            socket.assigns.user.id,
            current_calendar_date(socket),
            current_language(socket)
          )

        {:noreply,
         socket
         |> assign(:user_meals, user_meals)
         |> assign_blueprint_progress()
         |> push_event("create_meals", %{meals: user_meals})
         |> put_flash(:info, "User Meal Deleted")
         |> push_patch(to: ~p"/calendar", replace: true)}

      {:error, _changeset} ->
        {:noreply, socket}
    end
  end

  # "Shopping list" — build a shopping basket from the ingredients of every meal
  # in the week currently in view (same Monday–Sunday span as the grid, via
  # `week_bounds/1`), reusing the shared `Inventory` aggregation, then take the
  # user to their baskets to see/edit it.
  @impl true
  def handle_event("create_week_basket", _params, socket) do
    user_id = socket.assigns.user.id
    {first, last} = week_bounds(current_calendar_date(socket))

    case Mehungry.Inventory.get_basket_for_week(user_id, first) do
      nil ->
        locale = current_language(socket)

        date_label =
          "#{first.day} #{MehungryWeb.CalendarLive.Calendar.Locale.month_short(first, locale)}"

        title = gettext("Week of %{date}", date: date_label)

        case Mehungry.Inventory.create_basket_for_range(user_id, first, last, title) do
          {:ok, basket} ->
            {:noreply,
             socket
             |> put_flash(:info, gettext("Shopping list created for this week"))
             |> push_navigate(to: ~p"/basket?#{[basket_id: basket.id]}")}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, gettext("Could not create a shopping list"))}
        end

      existing ->
        # Already have a list for this week — just open it, don't duplicate.
        {:noreply, push_navigate(socket, to: ~p"/basket?#{[basket_id: existing.id]}")}
    end
  end

  # "Clear week" — wipe every meal in the week currently in view (the same
  # Monday–Sunday span the grid shows, via `week_bounds/1`). Guarded by a
  # confirm dialog on the button; refreshes the view the same way a single
  # delete does so the emptied week shows immediately.
  @impl true
  def handle_event("clear_week_meals", _params, socket) do
    user_id = socket.assigns.user.id
    {first, last} = week_bounds(current_calendar_date(socket))
    count = History.delete_user_meals_in_date_range(user_id, first, last)

    user_meals =
      load_and_format_user_meals(user_id, current_calendar_date(socket), current_language(socket))

    {:noreply,
     socket
     |> assign(:user_meals, user_meals)
     |> assign_blueprint_progress()
     |> push_event("create_meals", %{meals: user_meals})
     |> put_flash(:info, "Cleared #{count} #{ngettext("meal", "meals", count)} from this week")
     |> push_patch(to: ~p"/calendar", replace: true)}
  end

  # "Log again today" — clone an existing meal (with all its items) onto today.
  # Reloads the viewed week so the copy shows immediately when today is in view;
  # otherwise the flash confirms it landed on today.
  @impl true
  def handle_event("copy_meal_to_today", %{"id" => meal_id}, socket) do
    user_id = socket.assigns.user.id

    case History.duplicate_user_meal(user_id, meal_id, Date.utc_today()) do
      {:ok, _meal} ->
        user_meals =
          load_and_format_user_meals(user_id, current_calendar_date(socket), current_language(socket))

        {:noreply,
         socket
         |> assign(:user_meals, user_meals)
         |> assign_blueprint_progress()
         |> push_event("create_meals", %{meals: user_meals})
         |> put_flash(:info, "Copied to today")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not copy this meal")}
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

  @impl true
  def handle_async(:generate_week_card, {:ok, {:ok, graphic}}, socket) do
    {:noreply,
     socket
     |> assign(:share_generating, false)
     |> assign(:share_regenerate, false)
     |> assign(:share_posted, false)
     |> assign(:share_graphic, graphic)}
  end

  def handle_async(:generate_week_card, {:ok, {:error, :empty_week}}, socket) do
    {:noreply,
     socket
     |> assign(:share_generating, false)
     |> put_flash(:error, "This week has no meals yet — add some to share it.")}
  end

  def handle_async(:generate_week_card, {:ok, {:error, _reason}}, socket) do
    {:noreply,
     socket
     |> assign(:share_generating, false)
     |> put_flash(:error, "Could not create the card. Please try again.")}
  end

  def handle_async(:generate_week_card, {:exit, _reason}, socket) do
    {:noreply,
     socket
     |> assign(:share_generating, false)
     |> put_flash(:error, "Could not create the card. Please try again.")}
  end

  defp list_recipes(user) do
    Food.list_user_recipes_for_selection(user)
  end

  # A "Use this blueprint" arrival from a public preview (`?blueprint_id=`):
  # preselect it in the AI-plan dropdown (adding it to the list if the user
  # doesn't own/save it) so the panel opens ready to generate.
  defp maybe_preselect_blueprint(socket, id) when id in [nil, ""], do: socket

  defp maybe_preselect_blueprint(socket, id) do
    user = socket.assigns.user

    case load_selected_blueprint(user.id, id) do
      nil ->
        socket

      blueprint ->
        socket
        |> persist_followed_blueprint(blueprint.id)
        |> assign(:blueprints, prepend_blueprint(socket.assigns.blueprints, blueprint))
        |> assign(:preselected_blueprint_id, to_string(blueprint.id))
        |> assign(:active_blueprint, blueprint)
    end
  end

  # Prepends `blueprint` to the calendar's blueprint list when not already present
  # (nil is a no-op), so a followed/selected blueprint the user doesn't own is
  # still selectable in the panel.
  defp prepend_blueprint(blueprints, nil), do: blueprints

  defp prepend_blueprint(blueprints, blueprint) do
    if Enum.any?(blueprints, &(&1.id == blueprint.id)),
      do: blueprints,
      else: [blueprint | blueprints]
  end

  # Persists (or clears, with `nil`) the followed blueprint on the user's profile
  # so the selection survives reloads, keeping the in-socket profile fresh.
  # No-op when the user has no profile row yet.
  defp persist_followed_blueprint(socket, blueprint_id) do
    case socket.assigns[:user_profile] do
      nil ->
        socket

      profile ->
        case Accounts.set_followed_blueprint(profile, blueprint_id) do
          {:ok, updated} -> assign(socket, :user_profile, updated)
          {:error, _} -> socket
        end
    end
  end

  # Computes the blueprint-vs-calendar progress for the week currently in view,
  # but only when the user is "following" a blueprint (arrived via "Use this
  # blueprint"). Fully inert — no DB work — otherwise. The visible week is the
  # one anchored by `@particular_date` (nil ⇒ today), matching the calendar
  # Widget's `Date.beginning_of_week/1` framing.
  defp assign_blueprint_progress(socket) do
    case socket.assigns[:active_blueprint] do
      nil ->
        assign(socket, :blueprint_progress, nil)

      blueprint ->
        week_start = Date.beginning_of_week(current_calendar_date(socket))

        progress =
          Mehungry.MealBlueprints.calendar_progress(
            socket.assigns.user.id,
            blueprint,
            week_start
          )

        assign(socket, :blueprint_progress, progress)
    end
  end

  defp current_calendar_date(socket) do
    case socket.assigns[:particular_date] do
      date when is_binary(date) ->
        case Date.from_iso8601(date) do
          {:ok, d} -> d
          _ -> Date.utc_today()
        end

      %Date{} = d ->
        d

      _ ->
        Date.utc_today()
    end
  end

  # The blueprints offered in the AI-plan dropdown: the user's own (nutritionists)
  # plus any public blueprints they've saved to their profile, deduped by id.
  defp load_calendar_blueprints(user_id) do
    owned = Mehungry.MealBlueprints.list_blueprints_for_user(user_id)
    saved = Mehungry.MealBlueprints.list_saved_blueprints_for_user(user_id)

    (owned ++ saved) |> Enum.uniq_by(& &1.id)
  end

  # Lookup of the blueprint chosen in the AI-plan dropdown — one the user owns,
  # has saved, or that is public; nil when "None" (or an unknown/forbidden id).
  defp load_selected_blueprint(_user_id, id) when id in [nil, ""], do: nil

  defp load_selected_blueprint(user_id, id) do
    Mehungry.MealBlueprints.get_blueprint_for_generation(user_id, id)
  rescue
    Ecto.NoResultsError -> nil
  end

  # Reloads `@user_meals` (and the week's day notes) for the currently-viewed
  # week (anchored by `@particular_date`, defaulting to today).
  defp reload_week_meals(socket) do
    # Disconnected (first-paint) render does no DB work — the connected mount
    # loads the week's meals. Guarding here keeps apply_action/3 cheap on the
    # dead render too (see mount/3).
    if connected?(socket) do
      date = current_calendar_date(socket)
      meals = load_and_format_user_meals(socket.assigns.user.id, date, current_language(socket))

      socket
      |> assign(:user_meals, meals)
      |> assign(:day_notes, day_notes_for(socket.assigns.user.id, date))
      # Switching weeks shows that week's saved share card (if any) and drops any
      # in-progress "regenerate" view.
      |> assign(:share_regenerate, false)
      |> assign_latest_share_graphic()
    else
      socket
    end
  end

  # Loads the latest saved weekly-plan share card for the viewed week into
  # `@share_graphic` so the share modal shows it instead of forcing a regenerate.
  defp assign_latest_share_graphic(socket) do
    week_start = Date.beginning_of_week(current_calendar_date(socket))
    graphic = Food.latest_weekly_plan_graphic(socket.assigns.user.id, week_start)
    assign(socket, :share_graphic, graphic)
  end

  # The user's day notes for the week the given date falls in, as a
  # `%{Date => body}` map (one query, no N+1 over the 7 days).
  defp day_notes_for(user_id, %Date{} = date) do
    {first, last} = week_bounds(date)
    Mehungry.History.list_day_notes(user_id, first, last)
  end

  # Loads only the meals for the week the given date falls in (the calendar never
  # shows more than one week at a time), rather than the user's entire history.
  # Localizes ingredient names / unit labels / recipe titles to `locale` so the
  # calendar grid and the share card both show the user's language.
  defp load_and_format_user_meals(user_id, %Date{} = date, locale) do
    {first, last} = week_bounds(date)

    History.list_calendar_user_meals(user_id, first, last)
    |> History.format_user_meals(locale)
  end

  defp current_language(socket), do: Map.get(socket.assigns, :current_language, "en")

  # The Monday-anchored 7-day span the Widget renders (matches its `get_full_week`
  # and `assign_blueprint_progress`, all using `Date.beginning_of_week/1`).
  defp week_bounds(%Date{} = date) do
    first = Date.beginning_of_week(date)
    {first, Date.add(first, 6)}
  end

  defp build_result_message(created, 0),
    do: "Added #{created} meals to your calendar."

  defp build_result_message(created, skipped),
    do: "Added #{created} meals to your calendar (#{skipped} skipped due to errors)."
end
