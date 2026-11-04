defmodule MehungryWeb.NutritionistLive.ClientCalendar do
  use MehungryWeb, :live_view
  use ViewportHelpers

  alias Mehungry.Professionals
  alias Mehungry.Accounts
  alias Mehungry.History
  alias Mehungry.History.UserMeal
  alias Mehungry.Food
  alias Mehungry.Subscriptions
  alias Mehungry.AI.MealPlanGenerator

  @impl true
  def mount(%{"id" => client_id_str} = _params, _session, socket) do
    professional_id = socket.assigns.current_user.id
    client_id = String.to_integer(client_id_str)

    case Professionals.get_assignment(professional_id, client_id) do
      nil ->
        {:ok,
         socket |> put_flash(:error, gettext("Client not found.")) |> redirect(to: "/nutritionist/clients")}

      _assignment ->
        client = Accounts.get_user!(client_id)
        user_meals = load_and_format_user_meals(client_id, Date.utc_today())
        recipes = Food.list_user_recipes_for_selection(nil)

        # The client's own calorie target drives the editor's totals-vs-target
        # colouring (nil when the client has no profile/target set yet).
        profile = Accounts.get_user_profile_by_user_id(client_id)

        socket = assign_device_kind(socket)

        {:ok,
         socket
         |> assign(:client, client)
         |> assign(:client_id, client_id)
         |> assign(:user_meals, user_meals)
         |> assign(:recipes, recipes)
         |> assign(:particular_date, nil)
         |> assign(:calendar_view, "week_view")
         |> assign(:calorie_target, profile && profile.daily_calorie_target)
         |> assign(:pending_meal_type, nil)
         |> assign(:ai_plan_generating, false)
         |> assign(:ai_plan_task_ref, nil)
         |> assign(:ai_plan_result, nil)
         |> assign(:ai_quota_exceeded, false)
         |> assign(:child_ids, [])
         |> assign(:page_title, gettext("%{name}'s Meal Plan", name: client.name || client.email))}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params), do: socket

  defp apply_action(socket, :particular, %{"date" => date}) do
    # Week navigation patches here with no reload of its own, so load the
    # newly-viewed week's meals (the calendar only ever shows one week).
    socket = assign(socket, :particular_date, date)

    socket
    |> push_event("go_to_date", %{date: date})
    |> assign(
      :user_meals,
      load_and_format_user_meals(socket.assigns.client_id, current_calendar_date(socket))
    )
  end

  defp apply_action(socket, :new, %{"date" => start_date, "title" => title}) do
    if past_date?(start_date) do
      deny_past_date(socket)
    else
      socket
      |> assign(:page_title, gettext("Create Meal"))
      |> assign(:user_meal, struct(UserMeal))
      |> assign(:title, title)
      |> assign(:dates, %{start: start_date})
    end
  end

  defp apply_action(socket, :edit, %{"meal_id" => meal_id}) do
    user_meal = History.get_user_meal!(meal_id)

    cond do
      # Guard: nutritionists may only edit meals belonging to their assigned client.
      user_meal.user_id != socket.assigns.client_id ->
        socket
        |> put_flash(:error, gettext("Not authorized."))
        |> push_patch(to: "/nutritionist/clients/#{socket.assigns.client_id}/calendar")

      past_date?(user_meal.start_dt) ->
        deny_past_date(socket)

      true ->
        socket
        |> assign(:page_title, gettext("Edit Meal"))
        |> assign(:user_meal, user_meal)
        |> assign(:title, user_meal.title)
        |> assign(:dates, %{start: user_meal.start_dt, end: user_meal.end_dt})
    end
  end

  # Meals can only be assigned or edited from today forward; past dates are
  # read-only. Both the widget's add/edit affordances route through the `:new`
  # and `:edit` actions, so guarding here covers every entry point (including
  # direct URL navigation).
  defp past_date?(%NaiveDateTime{} = dt),
    do: Date.compare(NaiveDateTime.to_date(dt), Date.utc_today()) == :lt

  defp past_date?(date) when is_binary(date) do
    case Date.from_iso8601(date) do
      {:ok, d} -> Date.compare(d, Date.utc_today()) == :lt
      _ -> false
    end
  end

  defp deny_past_date(socket) do
    socket
    |> put_flash(:error, gettext("You can't assign meals on a past date — pick today or a future day."))
    |> push_patch(to: "/nutritionist/clients/#{socket.assigns.client_id}/calendar")
  end

  @impl true
  def handle_info({:initial_modal, %{"date" => start_date, "title" => title}}, socket) do
    client_id = socket.assigns.client_id

    {:noreply,
     push_patch(socket, to: "/nutritionist/clients/#{client_id}/calendar/#{start_date}/#{title}")}
  end

  @impl true
  def handle_info({:particular_date, %{"date" => date}}, socket) do
    client_id = socket.assigns.client_id
    {:noreply, push_patch(socket, to: "/nutritionist/clients/#{client_id}/calendar/#{date}")}
  end

  # AI draft task finished: record the nutritionist's usage, reload the viewed
  # week so the new meals show in the grid, and surface a result message.
  @impl true
  def handle_info({ref, result}, socket) when is_reference(ref) do
    Process.demonitor(ref, [:flush])

    if socket.assigns[:ai_plan_task_ref] == ref do
      case result do
        {:ok, created, skipped} ->
          Subscriptions.record_usage(socket.assigns.current_user.id, "meal_plan")

          user_meals =
            load_and_format_user_meals(socket.assigns.client_id, current_calendar_date(socket))

          {:noreply,
           socket
           |> assign(:ai_plan_generating, false)
           |> assign(:ai_plan_task_ref, nil)
           |> assign(:ai_plan_result, ai_result_message(length(created), skipped))
           |> assign(:user_meals, user_meals)}

        {:error, reason} ->
          {:noreply,
           socket
           |> assign(:ai_plan_generating, false)
           |> assign(:ai_plan_task_ref, nil)
           |> put_flash(:error, gettext("Could not generate plan: %{reason}", reason: inspect(reason)))}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _, _reason}, socket) when is_reference(ref) do
    if socket.assigns[:ai_plan_task_ref] == ref do
      {:noreply,
       socket
       |> assign(:ai_plan_generating, false)
       |> assign(:ai_plan_task_ref, nil)
       |> put_flash(:error, gettext("AI plan generation failed unexpectedly"))}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("delete_user_meal", %{"id" => id}, socket) do
    client_id = socket.assigns.client_id

    try do
      meal = History.get_user_meal!(String.to_integer(id))

      if meal.user_id == client_id do
        History.delete_user_meal(meal)
        user_meals = load_and_format_user_meals(client_id, current_calendar_date(socket))

        {:noreply,
         socket
         |> assign(:user_meals, user_meals)
         |> push_event("create_meals", %{meals: user_meals})}
      else
        {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
      end
    rescue
      Ecto.NoResultsError -> {:noreply, put_flash(socket, :error, gettext("Meal not found."))}
    end
  end

  @impl true
  def handle_event("go_to_date", %{"date" => date}, socket) do
    client_id = socket.assigns.client_id
    {:noreply, push_patch(socket, to: "/nutritionist/clients/#{client_id}/calendar/#{date}")}
  end

  @impl true
  def handle_event("edit_modal", %{"id" => id}, socket) do
    client_id = socket.assigns.client_id

    {:noreply, push_patch(socket, to: "/nutritionist/clients/#{client_id}/calendar/edit/#{id}")}
  end

  # In-cell add from the editor grid: open the add-meal modal pre-set to that day
  # and meal type. Past dates are read-only (the grid hides the affordance, but
  # guard here too for direct events).
  @impl true
  def handle_event("add_cell", %{"date" => date} = params, socket) do
    client_id = socket.assigns.client_id
    meal_type = case Map.get(params, "type", "") do "" -> nil; t -> t end

    if past_date?(date) do
      {:noreply, deny_past_date(socket)}
    else
      {:noreply,
       socket
       |> assign(:pending_meal_type, meal_type)
       |> push_patch(to: "/nutritionist/clients/#{client_id}/calendar/#{date}/Meal")}
    end
  end

  # AI draft: generate a week of meals onto the *client's* calendar, anchored to
  # the viewed week. The prompt is enriched with the client's patient-file data
  # (goal, conditions, calorie target, diet, foods to avoid, latest measurements)
  # so the plan is tailored to this client. Quota is drawn from the nutritionist
  # (the pro-tier account doing the work).
  @impl true
  def handle_event("ai_plan_week", params, socket) do
    nutritionist_id = socket.assigns.current_user.id
    prompt = params |> Map.get("prompt", "") |> String.trim()

    case Subscriptions.check_quota(nutritionist_id, "meal_plan") do
      :ok ->
        # The client's recorded profile drives the draft; the typed prompt is
        # optional extra guidance on top.
        preferences = build_client_preferences(prompt, socket)
        recipes = socket.assigns.recipes
        start_date = Date.beginning_of_week(current_calendar_date(socket))
        client_id = socket.assigns.client_id

        task =
          Task.async(fn ->
            MealPlanGenerator.run(preferences, recipes, start_date, client_id, nil)
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

  @impl true
  def handle_event("close-modal", _params, socket) do
    client_id = socket.assigns.client_id
    {:noreply, push_patch(socket, to: "/nutritionist/clients/#{client_id}/calendar")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-ink min-h-screen">
      <.modal
        :if={@live_action in [:new, :edit]}
        on_cancel={JS.patch("/nutritionist/clients/#{@client_id}/calendar")}
        id="client_calendar_modal"
        show
      >
        <div class="w-full h-full">
          <.live_component
            module={MehungryWeb.CalendarLive.MealFormComponent}
            id={@user_meal.id || :new}
            title={@user_meal.title || @title}
            meal_type={@user_meal.meal_type || @pending_meal_type}
            live_action={@live_action}
            recipes={@recipes}
            dates={@dates}
            current_user={@client}
            current_language={@current_language}
            return_to={"/nutritionist/clients/#{@client_id}/calendar"}
          />
        </div>
      </.modal>
      <!-- Banner -->
      <div class="bg-basil/10 border-b border-basil/30 px-4 py-2 flex items-center gap-3">
        <a href={"/nutritionist/clients/#{@client_id}"} class="text-basil hover:text-basil-soft">
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M10 19l-7-7m0 0l7-7m-7 7h18"
            />
          </svg>
        </a>
        <%= if @client.profile_pic do %>
          <img src={@client.profile_pic} class="w-6 h-6 rounded-full object-cover" />
        <% else %>
          <div class="w-6 h-6 rounded-full bg-basil flex items-center justify-center text-ink text-xs font-bold">
            {String.first(@client.name || "?")}
          </div>
        <% end %>
        <p class="text-parchment-dim text-sm">
          {gettext("Editing")} <span class="font-medium text-parchment">{@client.name || @client.email}</span>{gettext("'s meal plan")}
        </p>
      </div>

      <!-- Week-grid plan editor -->
      <div style="height: calc(100vh - 48px); overflow-y: auto;" class="bg-ink">
        <!-- AI draft (tailored to the client's recorded profile) -->
        <div class="px-3 sm:px-4 pt-3">
          <div class="flex justify-end">
            <button
              type="button"
              phx-click={Phoenix.LiveView.JS.toggle(to: "#nutri-ai-panel")}
              class="flex items-center gap-1.5 px-3 py-1.5 rounded-full border border-basil/40 text-basil-soft hover:text-basil hover:border-basil text-sm font-medium transition-colors"
            >
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z" />
              </svg>
              {gettext("AI draft week")}
            </button>
          </div>
          <div id="nutri-ai-panel" class="hidden mt-2 bg-ink-panel border border-ink-panel2 rounded-xl p-4">
            <h3 class="font-display font-medium text-parchment text-sm mb-1">
              {gettext("Draft %{name}'s week with AI", name: @client.name || @client.email)}
            </h3>
            <p class="text-parchment-dim/70 text-xs mb-3 max-w-prose">
              {gettext(
                "The draft is tailored to this client's recorded profile — goal, health conditions, calorie target, diet, and foods to avoid. Review and adjust before sharing."
              )}
            </p>
            <form phx-submit="ai_plan_week" class="flex flex-col sm:flex-row gap-3">
              <textarea
                name="prompt"
                rows="2"
                placeholder={gettext("Optional extra guidance… e.g. 'Mediterranean, 5 meals/day, no pork'")}
                class="flex-1 bg-ink text-parchment rounded-lg p-3 text-sm resize-none border border-ink-panel2 focus:border-basil focus:outline-none"
              ></textarea>
              <button
                type="submit"
                disabled={@ai_plan_generating}
                class="px-5 py-2 rounded-lg bg-basil hover:bg-basil-soft text-ink font-semibold text-sm self-end disabled:opacity-50 disabled:cursor-not-allowed transition"
              >
                <%= if @ai_plan_generating do %>
                  {gettext("Planning…")}
                <% else %>
                  {gettext("Generate")}
                <% end %>
              </button>
            </form>
            <p :if={@ai_plan_result} class="text-basil text-xs mt-3">{@ai_plan_result}</p>
            <div
              :if={@ai_quota_exceeded}
              class="mt-3 rounded-lg bg-amber-500/10 border border-amber-500/30 p-3 flex items-center justify-between gap-3"
            >
              <p class="text-amber-300 text-xs">
                {gettext("You've reached your AI meal plan limit for this month.")}
              </p>
              <.link
                navigate={~p"/upgrade"}
                class="flex-shrink-0 px-3 py-1.5 rounded-lg border border-amber-500/40 text-amber-300 hover:bg-amber-500/10 text-xs font-semibold transition"
              >
                {gettext("Upgrade")}
              </.link>
            </div>
          </div>
        </div>

        <.live_component
          module={MehungryWeb.CalendarLive.Calendar.Editor}
          id={:new}
          user_meals={@user_meals}
          particular_date={@particular_date}
          calendar_view={@calendar_view}
          user={@client}
          calorie_target={@calorie_target}
          device_width={@device_width}
          current_language={@current_language}
        />
      </div>
    </div>
    """
  end

  # Loads only the meals for the week the given date falls in, rather than the
  # client's entire history (the calendar only ever shows one week).
  defp load_and_format_user_meals(user_id, %Date{} = date) do
    first = Date.beginning_of_week(date)
    last = Date.add(first, 6)

    History.list_calendar_user_meals(user_id, first, last)
    |> History.format_user_meals()
  end

  defp ai_result_message(created, 0),
    do: gettext("Added %{n} meals to the plan.", n: created)

  defp ai_result_message(created, skipped),
    do: gettext("Added %{n} meals (%{s} skipped).", n: created, s: skipped)

  # Enriches the nutritionist's free-text prompt with the client's patient-file
  # data so the AI tailors the plan to this client. Only present fields are
  # included; with nothing on file it returns the prompt unchanged.
  defp build_client_preferences(prompt, socket) do
    professional_id = socket.assigns.current_user.id
    client_id = socket.assigns.client_id

    profile = Accounts.get_user_profile_by_user_id(client_id)
    record = Professionals.get_client_record_by_user(professional_id, client_id)
    intake = record && latest_intake(record.id)
    conditions = if record, do: Professionals.list_client_conditions(record.id), else: []

    lines =
      [
        intake && intake.goal && "Goal: #{humanize_token(intake.goal)}",
        intake && intake.sex && intake.age && "Sex / age: #{intake.sex}, #{intake.age}",
        intake && intake.activity_level && "Activity level: #{humanize_token(intake.activity_level)}",
        calorie_target_line(profile, intake),
        profile && profile.diet && "Diet: #{profile.diet}",
        conditions != [] && "Health conditions: #{Enum.map_join(conditions, ", ", & &1.name)}",
        avoid_foods_line(profile),
        intake && weight_line(intake)
      ]
      |> Enum.filter(& &1)

    context =
      case lines do
        [] -> nil
        _ -> "Client profile — tailor the plan to this client:\n- " <> Enum.join(lines, "\n- ")
      end

    preferences =
      [blank_to_nil(prompt), context]
      |> Enum.filter(& &1)
      |> Enum.join("\n\n")

    if preferences == "", do: gettext("A balanced, varied week of meals."), else: preferences
  end

  defp blank_to_nil(s) when is_binary(s), do: if(String.trim(s) == "", do: nil, else: s)
  defp blank_to_nil(_), do: nil

  defp latest_intake(professional_client_id) do
    case Professionals.list_intakes(professional_client_id) do
      [] -> nil
      intakes -> Enum.max_by(intakes, & &1.id)
    end
  end

  defp calorie_target_line(%{daily_calorie_target: kcal}, _intake) when is_integer(kcal),
    do: "Daily calorie target: #{kcal} kcal"

  defp calorie_target_line(_profile, %{tdee_kcal: kcal}) when is_integer(kcal),
    do: "Estimated daily energy need (TDEE): #{kcal} kcal"

  defp calorie_target_line(_profile, _intake), do: nil

  defp avoid_foods_line(%{avoid_foods: foods}) when is_list(foods) and foods != [],
    do: "Foods to avoid: #{Enum.join(foods, ", ")}"

  defp avoid_foods_line(_profile), do: nil

  defp weight_line(%{weight_kg: w, bmi: bmi}) when is_number(w) and is_number(bmi),
    do: "Current weight: #{w} kg (BMI #{Float.round(bmi / 1.0, 1)})"

  defp weight_line(%{weight_kg: w}) when is_number(w), do: "Current weight: #{w} kg"
  defp weight_line(_intake), do: nil

  defp humanize_token(value) when is_binary(value), do: String.replace(value, "_", " ")
  defp humanize_token(value), do: value

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
end
