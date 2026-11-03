defmodule MehungryWeb.NutritionistLive.ClientDetail do
  use MehungryWeb, :live_view

  alias Mehungry.Professionals
  alias Mehungry.Professionals.{ConsultationNote, ClientIntake}
  alias Mehungry.Professionals.Anthropometrics
  alias Mehungry.Professionals.DietaryHistory.Fields

  @energy_source_fields ~w(height_m weight_kg sex age activity_level)
  alias Mehungry.Accounts
  alias Mehungry.Health
  alias Mehungry.Plans, as: PlansCtx
  alias Mehungry.MealBlueprints
  alias Mehungry.ObanWorkers.NutritionistAgentWorker
  alias MehungryWeb.MeasurementChart

  @impl true
  def mount(%{"id" => client_id}, _session, socket) do
    professional_id = socket.assigns.current_user.id
    client_id_int = String.to_integer(client_id)

    case Professionals.get_assignment(professional_id, client_id_int) do
      nil ->
        {:ok,
         socket |> put_flash(:error, gettext("Client not found.")) |> redirect(to: "/nutritionist/clients")}

      _assignment ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(
            Mehungry.PubSub,
            NutritionistAgentWorker.topic(professional_id)
          )

          Professionals.subscribe_to_messages(professional_id)
        end

        client = Accounts.get_user!(client_id_int)

        appointments =
          Professionals.list_appointments_for_professional_client(professional_id, client_id_int)

        ratings = Professionals.list_ratings_for_client(client_id_int)
        meal_plans = PlansCtx.list_meal_plans_for_user(client_id_int)
        record = Professionals.get_client_record_by_user(professional_id, client_id_int)

        # Opening the thread reads the client's messages.
        Professionals.mark_thread_read(professional_id, client_id_int, professional_id)
        messages = Professionals.list_messages(professional_id, client_id_int)

        {:ok,
         socket
         |> assign(:client, client)
         |> assign(:client_id, client_id_int)
         |> assign(:appointments, appointments)
         |> assign(:ratings, ratings)
         |> assign(:meal_plans, meal_plans)
         |> assign(:page_title, gettext("Client: %{name}", name: client.name || client.email))
         |> assign(:ai_running, false)
         |> assign(:ai_steps, [])
         |> assign(:ai_result, nil)
         |> assign(:ai_error, nil)
         |> assign(:ai_preferences, "")
         |> assign(:record, record)
         |> assign(:onboarding_answers, Mehungry.Onboarding.answers_for_user(client_id_int))
         |> assign(:onboarding_locale, Gettext.get_locale(MehungryWeb.Gettext))
         |> assign(:conditions, client_conditions(record))
         |> assign(:all_conditions, Health.list_conditions())
         |> assign(:show_visit_form, false)
         |> assign(:intake_editing?, false)
         |> assign(:plan_options, load_plan_options(professional_id))
         |> assign(:assign_plan_form, new_assign_plan_form())
         |> assign(:messages, messages)
         |> assign(:message_body, "")
         |> load_intake()
         |> load_visits()
         |> load_weight_history()}
    end
  end

  # ── AI Assist events ──────────────────────────────────────────────────────────

  @impl true
  def handle_event("ai_assist", %{"preferences" => prefs}, socket) do
    professional_id = socket.assigns.current_user.id
    client = socket.assigns.client

    case NutritionistAgentWorker.enqueue(
           professional_id,
           socket.assigns.client_id,
           client.name || client.email,
           prefs
         ) do
      {:ok, _job} ->
        {:noreply,
         socket
         |> assign(:ai_running, true)
         |> assign(:ai_steps, [])
         |> assign(:ai_result, nil)
         |> assign(:ai_error, nil)
         |> assign(:ai_preferences, prefs)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not start AI assistant: %{reason}", reason: inspect(reason)))}
    end
  end

  @impl true
  def handle_event("ai_dismiss", _params, socket) do
    {:noreply,
     socket
     |> assign(:ai_running, false)
     |> assign(:ai_steps, [])
     |> assign(:ai_result, nil)
     |> assign(:ai_error, nil)}
  end

  # ── Messages ────────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("send_message", %{"body" => body}, socket) do
    professional_id = socket.assigns.current_user.id
    client_id = socket.assigns.client_id

    case Professionals.send_message(professional_id, client_id, professional_id, body) do
      {:ok, message} ->
        {:noreply,
         socket
         |> assign(:messages, append_message(socket.assigns.messages, message))
         |> assign(:message_body, "")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, gettext("Message can't be empty."))}
    end
  end

  # ── Health conditions (structured client↔condition link) ────────────────────────

  @impl true
  def handle_event("add_condition", %{"condition_id" => ""}, socket), do: {:noreply, socket}

  def handle_event("add_condition", %{"condition_id" => condition_id}, socket) do
    # A condition attaches to the client record; create it lazily if this is the
    # first thing recorded for the client.
    case ensure_record(socket) do
      {:ok, socket, record} ->
        Professionals.add_client_condition(record.id, condition_id)

        {:noreply,
         socket
         |> assign(:conditions, client_conditions(record))
         |> put_flash(:info, gettext("Condition added."))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not add the condition."))}
    end
  end

  def handle_event("remove_condition", %{"id" => condition_id}, socket) do
    case socket.assigns.record do
      nil ->
        {:noreply, socket}

      record ->
        Professionals.remove_client_condition(record.id, condition_id)
        {:noreply, assign(socket, :conditions, client_conditions(record))}
    end
  end

  # Open the full dietary-history editor, creating the record first if needed —
  # the platform user is implied by the client being viewed, so there is no picker.
  @impl true
  def handle_event("open_full_record", _params, socket) do
    case ensure_record(socket) do
      {:ok, socket, record} ->
        {:noreply, push_navigate(socket, to: ~p"/nutritionist/records/#{record.id}/edit")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not open the record: %{reason}", reason: inspect(reason)))}
    end
  end

  # ── Assign a saved plan to THIS client's calendar ───────────────────────────────

  @impl true
  def handle_event("assign_plan", %{"assign" => params}, socket) do
    professional_id = socket.assigns.current_user.id
    client = socket.assigns.client

    with {plan_id, ""} <- Integer.parse(params["plan_id"] || ""),
         {:ok, start_date} <- Date.from_iso8601(params["start_date"] || ""),
         %_{} = plan <- safe_get_plan(professional_id, plan_id) do
      {:ok, created, skipped, deleted} =
        MealBlueprints.import_plan_to_calendar(client.id, plan, start_date)

      {:noreply,
       socket
       |> assign(:assign_plan_form, new_assign_plan_form())
       |> put_flash(:info, assign_plan_message(created, skipped, deleted, client))}
    else
      _ ->
        {:noreply, put_flash(socket, :error, gettext("Pick a plan and a valid start date."))}
    end
  end

  # ── Visit (consultation note) events ────────────────────────────────────────────

  @impl true
  def handle_event("new_visit", _params, socket) do
    next_number = length(socket.assigns.visits) + 1

    changeset =
      Professionals.change_consultation_note(%ConsultationNote{
        visit_number: next_number,
        visit_date: Date.utc_today(),
        modality: "in_person"
      })

    {:noreply,
     socket
     |> assign(:show_visit_form, true)
     |> assign_visit_form(changeset)}
  end

  @impl true
  def handle_event("cancel_visit", _params, socket) do
    {:noreply, assign(socket, :show_visit_form, false)}
  end

  @impl true
  def handle_event("validate_visit", %{"consultation_note" => params} = payload, socket) do
    changeset =
      %ConsultationNote{}
      |> Professionals.change_consultation_note(params)
      |> Map.put(:action, :validate)
      |> prefill_from_appointment(payload["_target"], socket.assigns.appointments)

    {:noreply, assign_visit_form(socket, changeset)}
  end

  @impl true
  def handle_event("save_visit", %{"consultation_note" => params}, socket) do
    case ensure_record(socket) do
      {:ok, socket, record} ->
        attrs = Map.put(params, "professional_client_id", record.id)

        case Professionals.create_consultation_note(attrs) do
          {:ok, _note} ->
            {:noreply,
             socket
             |> assign(:show_visit_form, false)
             |> load_visits()
             |> load_weight_history()
             |> put_flash(:info, gettext("Visit recorded."))}

          {:error, changeset} ->
            {:noreply, assign_visit_form(socket, changeset)}
        end

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not save visit: %{reason}", reason: inspect(reason)))}
    end
  end

  # ── Progress dashboard ──────────────────────────────────────────────────────────

  def handle_event("select_metric", %{"metric" => metric}, socket) do
    context = socket.assigns.measurement_context

    {:noreply,
     socket
     |> assign(:selected_metric, metric)
     |> assign(:progress_chart_svg, MeasurementChart.chart_svg(socket.assigns.measurement_history, metric, context))
     |> assign(:progress_legend, MeasurementChart.legend_items(context, metric))}
  end

  # ── Intake (dietary history) events ─────────────────────────────────────────────

  @impl true
  def handle_event("edit_intake", _params, socket) do
    case ensure_record(socket) do
      {:ok, socket, record} ->
        intake = socket.assigns.intake || %ClientIntake{professional_client_id: record.id}

        {:noreply,
         socket
         |> assign(:intake_editing?, true)
         |> assign(:intake_form, to_form(new_intake_changeset(intake, record), as: :intake))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not start editing: %{reason}", reason: inspect(reason)))}
    end
  end

  def handle_event("validate_intake", %{"intake" => params} = payload, socket) do
    changeset =
      (socket.assigns.intake || %ClientIntake{})
      |> Professionals.change_intake(params)
      |> Map.put(:action, :validate)
      |> recompute_energy(payload["_target"])

    {:noreply, assign(socket, :intake_form, to_form(changeset, as: :intake))}
  end

  def handle_event("cancel_intake", _params, socket) do
    {:noreply, assign(socket, :intake_editing?, false)}
  end

  def handle_event("save_intake", %{"intake" => params}, socket) do
    case ensure_record(socket) do
      {:ok, socket, record} ->
        attrs = Map.put(params, "professional_client_id", record.id)

        result =
          case socket.assigns.intake do
            %ClientIntake{id: id} when not is_nil(id) ->
              Professionals.update_intake(socket.assigns.intake, attrs)

            _ ->
              Professionals.create_intake(attrs)
          end

        case result do
          {:ok, intake} ->
            {:noreply,
             socket
             |> assign(:intake, intake)
             |> assign(:intake_editing?, false)
             |> load_weight_history()
             |> put_flash(:info, gettext("Dietary history saved."))}

          {:error, changeset} ->
            {:noreply, assign(socket, :intake_form, to_form(changeset, as: :intake))}
        end

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, gettext("Could not save dietary history: %{reason}", reason: inspect(reason)))}
    end
  end

  # Lazily create the client's ProfessionalClient record on the first visit.
  defp ensure_record(%{assigns: %{record: nil}} = socket) do
    case Professionals.ensure_client_record(socket.assigns.current_user.id, socket.assigns.client) do
      {:ok, record} -> {:ok, assign(socket, :record, record), record}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp ensure_record(socket), do: {:ok, socket, socket.assigns.record}

  defp client_conditions(nil), do: []
  defp client_conditions(record), do: Professionals.list_client_conditions(record.id)

  # Read-only: the answers the client gave to the app's user-onboarding questions
  # (admin-authored, filled during their own onboarding), shown here on the file.
  defp onboarding_answers_panel(assigns) do
    ~H"""
    <div :if={@onboarding_answers != []} class="bg-ink-panel border border-ink-panel2 rounded-xl p-5 mb-6">
      <h2 class="text-parchment font-display font-semibold mb-4">{gettext("Onboarding answers")}</h2>
      <dl class="space-y-3">
        <div :for={{q, a} <- @onboarding_answers}>
          <dt class="text-xs font-semibold uppercase tracking-wide text-parchment-dim">
            {onboarding_prompt(q, a, @onboarding_locale)}
          </dt>
          <dd class="text-parchment text-sm mt-0.5">{onboarding_answer_text(q, a, @onboarding_locale)}</dd>
        </div>
      </dl>
    </div>
    """
  end

  defp onboarding_prompt(nil, a, _locale), do: a.prompt_snapshot || "—"
  defp onboarding_prompt(q, _a, locale), do: Mehungry.Onboarding.Question.prompt(q, locale)

  defp onboarding_answer_text(q, a, locale) do
    cond do
      a.value_text not in [nil, ""] ->
        a.value_text

      a.selected_options not in [nil, []] ->
        option_labels(q, a.selected_options, locale)

      true ->
        "—"
    end
  end

  defp option_labels(nil, keys, _locale), do: Enum.join(keys, ", ")

  defp option_labels(q, keys, locale) do
    q.options
    |> Enum.filter(&(&1.key in keys))
    |> Enum.map(&Mehungry.Onboarding.QuestionOption.label(&1, locale))
    |> case do
      [] -> Enum.join(keys, ", ")
      labels -> Enum.join(labels, ", ")
    end
  end

  # Conditions render as one more basic field in the Dietary History card (like
  # "Sex"): a small label, the linked conditions as values, and a minimal picker.
  defp conditions_panel(assigns) do
    linked_ids = Enum.map(assigns.conditions, & &1.id)

    assigns =
      assign(assigns, :available_conditions, Enum.reject(assigns.all_conditions, &(&1.id in linked_ids)))

    ~H"""
    <div class="mt-6 mb-2 pt-5 border-t border-ink-panel2">
      <h3 class="text-xs font-semibold uppercase tracking-wide text-parchment-dim mb-3">
        {gettext("Health conditions")}
      </h3>

      <div class="flex flex-wrap items-center gap-2">
        <%= if Enum.empty?(@conditions) do %>
          <span class="text-parchment-dim text-sm italic">{gettext("None recorded yet")}</span>
        <% else %>
          <%= for condition <- @conditions do %>
            <span class="inline-flex items-center gap-2 pl-3 pr-2 py-1 rounded-full bg-paprika/20 text-paprika text-xs">
              {condition.name}
              <.link
                navigate={~p"/nutritionist/research/notes?condition_id=#{condition.id}"}
                class="inline-flex items-center gap-0.5 text-basil hover:underline"
                title={gettext("Open my notes for %{name}", name: condition.name)}
              >
                <.icon name="hero-document-text" class="w-3 h-3" /> {gettext("Notes")}
              </.link>
              <button
                type="button"
                phx-click="remove_condition"
                phx-value-id={condition.id}
                aria-label={gettext("Remove %{name}", name: condition.name)}
                class="hover:text-parchment"
              >
                ✕
              </button>
            </span>
          <% end %>
        <% end %>

        <form
          :if={not Enum.empty?(@available_conditions)}
          phx-submit="add_condition"
          class="inline-flex items-center gap-2"
        >
          <select
            name="condition_id"
            class="bg-ink border border-ink-panel2 rounded-lg px-2.5 py-1.5 text-parchment text-xs"
          >
            <option value="">{gettext("+ Add condition")}</option>
            <%= for condition <- @available_conditions do %>
              <option value={condition.id}>{condition.name}</option>
            <% end %>
          </select>
          <.action variant={:secondary} size={:sm} type="submit">{gettext("Add")}</.action>
        </form>
      </div>
    </div>
    """
  end

  defp load_visits(socket) do
    visits =
      case socket.assigns.record do
        nil -> []
        record -> Enum.reverse(Professionals.list_consultation_notes(record.id))
      end

    noted_ids =
      for v <- visits, v.appointment_id, into: MapSet.new(), do: v.appointment_id

    socket
    |> assign(:visits, visits)
    |> assign(:noted_appointment_ids, noted_ids)
  end

  # When the nutritionist picks an appointment this visit corresponds to, stamp
  # the visit date from it (only on the appointment-field change, so an edited
  # date is never clobbered). Appointments are already scoped to this
  # professional+client, so only a legitimately-owned appointment can be linked.
  defp prefill_from_appointment(changeset, ["consultation_note", "appointment_id"], appointments) do
    with id when not is_nil(id) <- Ecto.Changeset.get_field(changeset, :appointment_id),
         %{scheduled_at: %NaiveDateTime{} = at} <- Enum.find(appointments, &(&1.id == id)) do
      Ecto.Changeset.put_change(changeset, :visit_date, NaiveDateTime.to_date(at))
    else
      _ -> changeset
    end
  end

  defp prefill_from_appointment(changeset, _target, _appointments), do: changeset

  defp appointment_options(appointments) do
    for a <- appointments do
      {"#{Calendar.strftime(a.scheduled_at, "%b %d, %Y")} — #{a.title}", a.id}
    end
  end

  # Select options for every importable (status "completed") plan the
  # nutritionist owns, labelled "Blueprint — Plan", newest plan first.
  defp load_plan_options(professional_id) do
    for bp <- MealBlueprints.list_blueprints_for_user(professional_id),
        plan <- MealBlueprints.list_plans_for_blueprint(professional_id, bp.id),
        plan.status == "completed" do
      {"#{bp.name} — #{plan.name}", plan.id}
    end
  end

  defp new_assign_plan_form do
    to_form(%{"plan_id" => "", "start_date" => Date.to_iso8601(Date.utc_today())}, as: :assign)
  end

  # Owner-scoped plan fetch — `get_plan!/2` raises if the plan isn't this
  # professional's, so a nutritionist can only push their own plans.
  defp safe_get_plan(professional_id, plan_id) do
    MealBlueprints.get_plan!(professional_id, plan_id)
  rescue
    Ecto.NoResultsError -> nil
  end

  defp assign_plan_message(created, skipped, deleted, client) do
    whose = client.name || client.email

    [
      gettext("Added %{created} meals to %{whose}'s calendar", created: created, whose: whose),
      deleted > 0 &&
        ngettext(
          ", replacing %{count} existing meal that week",
          ", replacing %{count} existing meals that week",
          deleted,
          count: deleted
        ),
      skipped > 0 && gettext(" (%{skipped} skipped)", skipped: skipped),
      "."
    ]
    |> Enum.reject(&(&1 == false))
    |> Enum.join()
  end

  defp assign_visit_form(socket, changeset),
    do: assign(socket, :visit_form, to_form(changeset))

  defp load_intake(socket) do
    intake =
      case socket.assigns.record do
        nil -> nil
        record -> Professionals.get_latest_intake(record.id)
      end

    assign(socket, :intake, intake)
  end

  # Loads the client's full body-measurement history + intake reference values and
  # builds the progress dashboard (KPI cards for every metric + the detail chart
  # for the selected one). See `MehungryWeb.MeasurementChart`.
  defp load_weight_history(socket) do
    {history, context} =
      case socket.assigns.record do
        nil -> {[], %{}}
        record -> {Professionals.measurement_history(record.id), Professionals.measurement_context(record.id)}
      end

    available = MeasurementChart.available_metrics(history)
    selected = MeasurementChart.pick_metric(socket.assigns[:selected_metric], available)

    socket
    |> assign(:measurement_history, history)
    |> assign(:measurement_context, context)
    |> assign(:available_metrics, available)
    |> assign(:selected_metric, selected)
    |> assign(:progress_cards, MeasurementChart.cards(history))
    |> assign(:progress_chart_svg, MeasurementChart.chart_svg(history, selected, context))
    |> assign(:progress_legend, MeasurementChart.legend_items(context, selected))
  end

  # ── PubSub messages ───────────────────────────────────────────────────────────

  @impl true
  def handle_info({:nutritionist_agent, {:started, client_name}}, socket) do
    {:noreply,
     socket
     |> assign(:ai_running, true)
     |> assign(:ai_steps, ["Starting analysis for #{client_name}…"])
     |> assign(:ai_result, nil)
     |> assign(:ai_error, nil)}
  end

  def handle_info({:nutritionist_agent, {:step, label}}, socket) do
    steps = socket.assigns.ai_steps ++ [label]
    {:noreply, assign(socket, :ai_steps, steps)}
  end

  def handle_info({:nutritionist_agent, {:done, summary}}, socket) do
    {:noreply,
     socket
     |> assign(:ai_running, false)
     |> assign(:ai_result, summary)}
  end

  def handle_info({:nutritionist_agent, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:ai_running, false)
     |> assign(:ai_error, reason)}
  end

  # A new message in the thread currently open: append it and (since the
  # nutritionist is looking) mark the client's messages read.
  def handle_info({:assignment_message, %{client_id: cid} = message}, socket) do
    if cid == socket.assigns.client_id do
      professional_id = socket.assigns.current_user.id
      Professionals.mark_thread_read(professional_id, cid, professional_id)
      {:noreply, assign(socket, :messages, append_message(socket.assigns.messages, message))}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # Append a message unless it's already in the list (the sender appends
  # optimistically and then also receives its own broadcast echo).
  defp append_message(messages, message) do
    if Enum.any?(messages, &(&1.id == message.id)), do: messages, else: messages ++ [message]
  end

  # ── render ────────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto">
      <!-- Header -->
      <div class="flex items-center gap-4 mb-6">
        <a href="/nutritionist/clients" class="text-parchment-dim hover:text-parchment">
          <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M10 19l-7-7m0 0l7-7m-7 7h18"
            />
          </svg>
        </a>
        <%= if @client.profile_pic do %>
          <img src={@client.profile_pic} class="w-12 h-12 rounded-full object-cover" />
        <% else %>
          <div class="w-12 h-12 rounded-full bg-basil flex items-center justify-center text-ink font-bold">
            {String.first(@client.name || "?")}
          </div>
        <% end %>
        <div>
          <h1 class="text-xl font-display font-bold text-parchment">
            {@client.name || @client.email}
          </h1>
          <p class="text-parchment-dim text-sm">{@client.email}</p>
        </div>
        <div class="ml-auto flex gap-2">
          <.action variant={:primary} size={:sm} href={"/nutritionist/clients/#{@client_id}/calendar"}>
            <svg
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
              stroke-width="2"
              stroke="currentColor"
              class="size-4 flex-shrink-0"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="M6.75 3v2.25M17.25 3v2.25M3 18.75V7.5a2.25 2.25 0 0 1 2.25-2.25h13.5A2.25 2.25 0 0 1 21 7.5v11.25m-18 0A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75m-18 0v-7.5A2.25 2.25 0 0 1 5.25 9h13.5A2.25 2.25 0 0 1 21 11.25v7.5"
              />
            </svg>
            {gettext("View Plan")}
          </.action>
          <.action
            variant={:secondary}
            size={:sm}
            href={"/nutritionist/appointments?client_id=#{@client_id}"}
          >
            {gettext("Schedule Appointment")}
          </.action>
          <.action variant={:secondary} size={:sm} phx-click="open_full_record">
            {gettext("Open full record")}
          </.action>
        </div>
      </div>

      <!-- AI Assist panel -->
      <div class="bg-ink-panel border border-ink-panel2 rounded-xl p-5 mb-6">
        <div class="flex items-center justify-between mb-3">
          <div class="flex items-center gap-2">
            <svg class="w-4 h-4 text-basil" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M9.663 17h4.673M12 3v1m6.364 1.636l-.707.707M21 12h-1M4 12H3m3.343-5.657l-.707-.707m2.828 9.9a5 5 0 117.072 0l-.548.547A3.374 3.374 0 0014 18.469V19a2 2 0 11-4 0v-.531c0-.895-.356-1.754-.988-2.386l-.548-.547z"
              />
            </svg>
            <h2 class="text-parchment font-semibold text-sm">{gettext("AI Meal Plan Assistant")}</h2>
          </div>
          <%= if @ai_result || @ai_error do %>
            <button phx-click="ai_dismiss" class="text-parchment-dim hover:text-parchment text-xs">
              {gettext("Dismiss")}
            </button>
          <% end %>
        </div>

        <%= if not @ai_running and is_nil(@ai_result) and is_nil(@ai_error) do %>
          <!-- Idle state: show form -->
          <.form for={%{}} phx-submit="ai_assist" class="flex gap-2">
            <input
              type="text"
              name="preferences"
              value={@ai_preferences}
              placeholder={gettext("Dietary notes for this client, e.g. 'low-carb, avoid shellfish'")}
              class="flex-1 bg-ink-panel2 border border-ink-panel2 rounded-lg px-3 py-2 text-parchment text-sm placeholder-parchment-dim focus:outline-none focus:border-paprika"
            />
            <button
              type="submit"
              class="bg-paprika hover:bg-paprika-soft text-ink text-sm font-medium px-4 py-2 rounded-lg transition whitespace-nowrap"
            >
              {gettext("Draft 7-day Plan")}
            </button>
          </.form>
        <% end %>

        <!-- Running: streaming steps -->
        <%= if @ai_running or @ai_steps != [] do %>
          <div class="space-y-1.5 mt-2">
            <%= for {step, idx} <- Enum.with_index(@ai_steps) do %>
              <div class="flex items-center gap-2">
                <%= if idx == length(@ai_steps) - 1 and @ai_running do %>
                  <!-- Latest step: animated dot -->
                  <span class="w-2 h-2 rounded-full bg-basil animate-pulse shrink-0"></span>
                <% else %>
                  <svg
                    class="w-3.5 h-3.5 text-basil shrink-0"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2.5"
                      d="M5 13l4 4L19 7"
                    />
                  </svg>
                <% end %>
                <span class={[
                  "text-sm",
                  if(idx == length(@ai_steps) - 1 and @ai_running,
                    do: "text-parchment",
                    else: "text-parchment-dim"
                  )
                ]}>
                  {step}
                </span>
              </div>
            <% end %>
          </div>
        <% end %>

        <!-- Done: show result -->
        <%= if @ai_result do %>
          <div class="mt-3 p-3 bg-basil/10 border border-basil/30 rounded-lg">
            <p class="text-basil text-sm whitespace-pre-wrap">{@ai_result}</p>
          </div>
          <div class="mt-3 flex gap-2">
            <a
              href={"/nutritionist/clients/#{@client_id}/calendar"}
              class="text-sm bg-paprika hover:bg-paprika-soft text-ink px-3 py-1.5 rounded-lg transition"
            >
              {gettext("View Plan →")}
            </a>
            <button
              phx-click="ai_dismiss"
              class="text-sm bg-ink-panel2 hover:bg-ink text-parchment-dim px-3 py-1.5 rounded-lg transition"
            >
              {gettext("Draft Another")}
            </button>
          </div>
        <% end %>

        <!-- Error state -->
        <%= if @ai_error do %>
          <div class="mt-3 p-3 bg-red-900/30 border border-red-700/40 rounded-lg">
            <p class="text-red-300 text-sm">{@ai_error}</p>
          </div>
          <button
            phx-click="ai_dismiss"
            class="mt-2 text-sm text-parchment-dim hover:text-parchment"
          >
            {gettext("Try again")}
          </button>
        <% end %>
      </div>

      <!-- Assign a saved plan -->
      <div class="bg-ink-panel border border-ink-panel2 rounded-xl p-5 mb-6">
        <div class="flex items-center gap-2 mb-3">
          <svg class="w-4 h-4 text-basil" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-3 7h3m-3 4h3m-6-4h.01M9 16h.01"
            />
          </svg>
          <h2 class="text-parchment font-semibold text-sm">{gettext("Assign a saved plan")}</h2>
        </div>

        <%= if @plan_options == [] do %>
          <p class="text-parchment-dim text-sm">
            {gettext("You have no completed plans yet.")}
            <.link navigate={~p"/nutritionist/blueprints"} class="text-basil hover:underline">
              {gettext("Build one in Meal Blueprints →")}
            </.link>
          </p>
        <% else %>
          <p class="text-parchment-dim text-sm mb-3">
            {gettext("Lay one of your plans onto %{name}'s calendar. The plan's 7 days start from the chosen date —", name: @client.name || @client.email)}
            <span class="text-paprika-soft">{gettext("any meals already on that week are replaced.")}</span>
          </p>
          <.form for={@assign_plan_form} phx-submit="assign_plan" class="flex flex-wrap items-end gap-3">
            <div class="flex-1 min-w-[12rem]">
              <label class="block text-sm text-parchment-dim mb-1">{gettext("Plan")}</label>
              <.input
                field={@assign_plan_form[:plan_id]}
                type="select"
                prompt={gettext("Choose a plan…")}
                options={@plan_options}
              />
            </div>
            <div>
              <label class="block text-sm text-parchment-dim mb-1">{gettext("Start date")}</label>
              <.input field={@assign_plan_form[:start_date]} type="date" />
            </div>
            <.action
              variant={:primary}
              size={:sm}
              type="submit"
              data-confirm={gettext("This replaces that whole week on %{name}'s calendar — any meals already logged there will be deleted. Continue?", name: @client.name || @client.email)}
            >
              {gettext("Add to calendar")}
            </.action>
          </.form>
        <% end %>
      </div>

      <!-- Messages -->
      <div class="bg-ink-panel border border-ink-panel2 rounded-xl p-5 mb-6">
        <div class="flex items-center gap-2 mb-3">
          <svg class="w-4 h-4 text-basil" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z"
            />
          </svg>
          <h2 class="text-parchment font-display font-semibold">
            {gettext("Messages with %{name}", name: @client.name || @client.email)}
          </h2>
        </div>
        <.message_thread
          messages={@messages}
          current_user_id={@current_user.id}
          body={@message_body}
          placeholder={gettext("Message your client…")}
        />
      </div>

      {intake_panel(assigns)}

      {onboarding_answers_panel(assigns)}

      <!-- Progress trend -->
      <div class="bg-ink-panel border border-ink-panel2 rounded-xl p-5 mb-6">
        <div class="flex items-center justify-between mb-4 gap-4">
          <h2 class="text-parchment font-display font-semibold">{gettext("Progress trend")}</h2>
          <span :if={@progress_cards != []} class="text-parchment-dim text-xs">
            {gettext("tap a metric to chart it")}
          </span>
        </div>
        <%= if @progress_cards != [] do %>
          <MeasurementChart.progress_dashboard
            cards={@progress_cards}
            selected={@selected_metric}
            chart={@progress_chart_svg}
            legend={@progress_legend}
          />
        <% else %>
          <p class="text-parchment-dim text-sm">
            {gettext("Not enough data yet — recorded measurements (weight, body fat, waist, muscle mass) will chart here once there are at least two readings.")}
          </p>
        <% end %>
      </div>

      <!-- Client record: visits -->
      <div class="bg-ink-panel border border-ink-panel2 rounded-xl p-5 mb-6">
        <div class="flex items-center justify-between mb-4">
          <div>
            <h2 class="text-parchment font-display font-semibold">{gettext("Client Record — Visits")}</h2>
            <%= if @record do %>
              <.link
                navigate={~p"/nutritionist/records/#{@record.id}"}
                class="text-parchment-dim hover:text-parchment text-xs"
              >
                {gettext("View full dietary history →")}
              </.link>
            <% else %>
              <p class="text-parchment-dim text-xs">{gettext("No dietary-history record yet.")}</p>
            <% end %>
          </div>
          <.action variant={:secondary} size={:sm} phx-click="new_visit">
            {gettext("+ New visit")}
          </.action>
        </div>

        <%= if Enum.empty?(@visits) do %>
          <p class="text-parchment-dim text-sm">{gettext("No visits recorded yet.")}</p>
        <% else %>
          <div class="space-y-2 max-h-96 overflow-y-auto pr-1">
            <%= for visit <- @visits do %>
              <div class="border border-ink-panel2 rounded-lg overflow-hidden">
                <!-- Header: basic info only -->
                <div
                  class="flex items-center gap-3 px-3 py-2.5 cursor-pointer select-none hover:bg-black/20"
                  phx-click={
                    JS.toggle(to: "#visit-body-#{visit.id}")
                    |> JS.toggle_class("rotate-180", to: "#visit-chevron-#{visit.id}")
                  }
                >
                  <%= if visit.visit_number do %>
                    <span class="px-2 py-0.5 rounded-full bg-paprika/20 text-paprika text-xs shrink-0">
                      {gettext("Visit %{number}", number: visit.visit_number)}
                    </span>
                  <% end %>
                  <span class="text-parchment text-sm">
                    {if visit.visit_date,
                      do: Calendar.strftime(visit.visit_date, "%b %d, %Y"),
                      else: "—"}
                  </span>
                  <span class="px-2 py-0.5 rounded-full bg-ink-panel2 text-parchment-dim text-xs">
                    {modality_label(visit.modality)}
                  </span>
                  <%= if visit.weight_kg do %>
                    <span class="text-parchment-dim text-xs">{visit.weight_kg} kg</span>
                  <% end %>
                  <%= if visit.appointment_id do %>
                    <span class="flex items-center gap-1 text-basil text-xs" title={gettext("Linked to an appointment")}>
                      <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          stroke-width="2"
                          d="M13.828 10.172a4 4 0 010 5.656l-3 3a4 4 0 01-5.656-5.656l1.5-1.5m8.656-1.172a4 4 0 010-5.656l3-3a4 4 0 115.656 5.656l-1.5 1.5"
                        />
                      </svg>
                      {gettext("Appointment")}
                    </span>
                  <% end %>
                  <svg
                    id={"visit-chevron-#{visit.id}"}
                    class="w-4 h-4 text-parchment-dim ml-auto shrink-0 transition-transform"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M19 9l-7 7-7-7"
                    />
                  </svg>
                </div>
                <!-- Body: full notes, hidden until expand -->
                <div
                  id={"visit-body-#{visit.id}"}
                  class="hidden px-3 pb-3 pt-1 border-t border-ink-panel2"
                >
                  <%= if visit.body do %>
                    <p class="text-parchment text-sm whitespace-pre-line mt-2">{visit.body}</p>
                  <% else %>
                    <p class="text-parchment-dim text-sm mt-2 italic">{gettext("No notes recorded.")}</p>
                  <% end %>
                  <%= if visit.todo do %>
                    <div class="mt-3 pt-3 border-t border-ink-panel2">
                      <p class="text-xs text-parchment-dim mb-1">{gettext("To do")}</p>
                      <p class="text-parchment text-sm whitespace-pre-line">{visit.todo}</p>
                    </div>
                  <% end %>
                  <%= if visit.appointment do %>
                    <div class="mt-3 pt-3 border-t border-ink-panel2">
                      <p class="text-xs text-parchment-dim mb-1">{gettext("Linked appointment")}</p>
                      <p class="text-parchment text-sm">
                        {visit.appointment.title} — {Calendar.strftime(
                          visit.appointment.scheduled_at,
                          "%b %d, %Y"
                        )}
                      </p>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>

      <!-- New visit modal -->
      <%= if @show_visit_form do %>
        <.modal id="new-visit-modal" show on_cancel={JS.push("cancel_visit")}>
          <h2 class="text-lg font-display font-bold text-parchment mb-4">{gettext("New visit")}</h2>
          <.form
            for={@visit_form}
            id="new-visit-form"
            phx-change="validate_visit"
            phx-submit="save_visit"
            class="space-y-4"
          >
            <div class="grid grid-cols-2 gap-4">
              <.labeled label={gettext("Visit date")}>
                <.input field={@visit_form[:visit_date]} type="date" />
              </.labeled>
              <.labeled label={gettext("Visit #")}>
                <.input field={@visit_form[:visit_number]} type="number" />
              </.labeled>
              <.labeled label={gettext("Modality")}>
                <.input
                  field={@visit_form[:modality]}
                  type="select"
                  options={[{gettext("In person"), "in_person"}, {gettext("Phone"), "phone"}, {gettext("Online"), "online"}]}
                />
              </.labeled>
              <.labeled label={gettext("Weight (kg)")}>
                <.input field={@visit_form[:weight_kg]} type="number" step="any" />
              </.labeled>
              <.labeled label={gettext("Body fat (%)")}>
                <.input field={@visit_form[:body_fat_percentage]} type="number" step="any" />
              </.labeled>
              <.labeled label={gettext("Waist (cm)")}>
                <.input field={@visit_form[:waist_cm]} type="number" step="any" />
              </.labeled>
              <.labeled label={gettext("Muscle mass (kg)")}>
                <.input field={@visit_form[:muscle_mass_kg]} type="number" step="any" />
              </.labeled>
            </div>
            <%= if @appointments != [] do %>
              <.labeled label={gettext("Linked appointment")}>
                <.input
                  field={@visit_form[:appointment_id]}
                  type="select"
                  prompt={gettext("— none —")}
                  options={appointment_options(@appointments)}
                />
              </.labeled>
            <% end %>
            <.labeled label={gettext("Notes")}>
              <.input field={@visit_form[:body]} type="textarea" />
            </.labeled>
            <.labeled label={gettext("To do")}>
              <.input field={@visit_form[:todo]} type="textarea" />
            </.labeled>
            <div class="flex gap-2 pt-1">
              <.action variant={:primary} size={:sm} type="submit">{gettext("Save visit")}</.action>
              <.action variant={:ghost} size={:sm} type="button" phx-click="cancel_visit">
                {gettext("Cancel")}
              </.action>
            </div>
          </.form>
        </.modal>
      <% end %>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <!-- Appointment history -->
        <div class="bg-ink-panel border border-ink-panel2 rounded-xl p-5">
          <h2 class="text-parchment font-display font-semibold mb-4">{gettext("Appointment History")}</h2>
          <%= if Enum.empty?(@appointments) do %>
            <p class="text-parchment-dim text-sm">{gettext("No appointments yet.")}</p>
          <% else %>
            <div class="space-y-3 max-h-64 overflow-y-auto">
              <%= for appt <- @appointments do %>
                <div class="border-b border-ink-panel2 pb-3 last:border-0">
                  <div class="flex items-start justify-between">
                    <p class="text-parchment text-sm font-medium">{appt.title}</p>
                    <span class="text-parchment-dim text-xs shrink-0 ml-2">
                      {Calendar.strftime(appt.scheduled_at, "%b %d, %Y")}
                    </span>
                  </div>
                  <%= if appt.notes do %>
                    <p class="text-parchment-dim text-xs mt-1">{appt.notes}</p>
                  <% end %>
                  <%= if MapSet.member?(@noted_appointment_ids, appt.id) do %>
                    <span class="inline-flex items-center gap-1 mt-1.5 px-2 py-0.5 rounded-full bg-basil/15 text-basil text-xs">
                      <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          stroke-width="2.5"
                          d="M5 13l4 4L19 7"
                        />
                      </svg>
                      {gettext("Visit note recorded")}
                    </span>
                  <% end %>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>

        <!-- Meal plan ratings -->
        <div class="bg-ink-panel border border-ink-panel2 rounded-xl p-5">
          <h2 class="text-parchment font-display font-semibold mb-4">{gettext("Meal Plan Ratings")}</h2>
          <%= if Enum.empty?(@ratings) do %>
            <p class="text-parchment-dim text-sm">{gettext("No ratings submitted yet.")}</p>
          <% else %>
            <div class="space-y-3 max-h-64 overflow-y-auto">
              <%= for rating <- @ratings do %>
                <div class="border-b border-ink-panel2 pb-3 last:border-0">
                  <div class="flex items-center justify-between">
                    <div class="flex items-center gap-1">
                      <%= for i <- 1..5 do %>
                        <svg
                          class={[
                            "w-4 h-4",
                            if(i <= rating.score, do: "text-yellow-400", else: "text-ink-panel2")
                          ]}
                          fill="currentColor"
                          viewBox="0 0 20 20"
                        >
                          <path d="M9.049 2.927c.3-.921 1.603-.921 1.902 0l1.07 3.292a1 1 0 00.95.69h3.462c.969 0 1.371 1.24.588 1.81l-2.8 2.034a1 1 0 00-.364 1.118l1.07 3.292c.3.921-.755 1.688-1.54 1.118l-2.8-2.034a1 1 0 00-1.175 0l-2.8 2.034c-.784.57-1.838-.197-1.539-1.118l1.07-3.292a1 1 0 00-.364-1.118L2.98 8.72c-.783-.57-.38-1.81.588-1.81h3.461a1 1 0 00.951-.69l1.07-3.292z" />
                        </svg>
                      <% end %>
                      <span class={[
                        "text-xs px-2 py-0.5 rounded-full ml-1",
                        rating.rating_type == "daily" && "bg-blue-500/20 text-blue-400",
                        rating.rating_type == "weekly" && "bg-purple-500/20 text-purple-400"
                      ]}>
                        {String.capitalize(rating.rating_type)}
                      </span>
                    </div>
                    <span class="text-parchment-dim text-xs">
                      {Calendar.strftime(rating.inserted_at, "%b %d")}
                    </span>
                  </div>
                  <%= if rating.comment do %>
                    <p class="text-parchment-dim text-xs mt-1 italic">"{rating.comment}"</p>
                  <% end %>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>

      <!-- Meal plans history -->
      <%= if not Enum.empty?(@meal_plans) do %>
        <div class="bg-ink-panel border border-ink-panel2 rounded-xl p-5 mt-6">
          <h2 class="text-parchment font-display font-semibold mb-4">{gettext("Meal Plan History")}</h2>
          <div class="space-y-2">
            <%= for plan <- @meal_plans do %>
              <div class="flex items-center justify-between py-2 border-b border-ink-panel2 last:border-0">
                <div>
                  <p class="text-parchment text-sm">{plan.title}</p>
                  <p class="text-parchment-dim text-xs">{plan.description}</p>
                </div>
                <span class="text-parchment-dim text-xs">
                  {Calendar.strftime(plan.inserted_at, "%b %d, %Y")}
                </span>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  attr :label, :string, required: true
  slot :inner_block, required: true

  defp labeled(assigns) do
    ~H"""
    <div>
      <label class="block text-sm text-parchment-dim mb-1">{@label}</label>
      {render_slot(@inner_block)}
    </div>
    """
  end

  # ── Intake (dietary history) panel ──────────────────────────────────────────────

  defp intake_panel(assigns) do
    ~H"""
    <div class="bg-ink-panel border border-ink-panel2 rounded-xl p-5 mb-6">
      <div class="flex items-center justify-between mb-4">
        <div>
          <h2 class="text-parchment font-display font-semibold">{gettext("Dietary History")}</h2>
          <%= if @record do %>
            <.link
              navigate={~p"/nutritionist/records/#{@record.id}"}
              class="text-parchment-dim hover:text-parchment text-xs"
            >
              {gettext("Open full record →")}
            </.link>
          <% end %>
        </div>
        <%= if not @intake_editing? do %>
          <.action variant={:secondary} size={:sm} phx-click="edit_intake">
            {if @intake, do: gettext("Edit"), else: gettext("Add dietary history")}
          </.action>
        <% end %>
      </div>

      <%= cond do %>
        <% @intake_editing? -> %>
          {intake_form(assigns)}
        <% @intake -> %>
          {intake_display(assigns)}
        <% true -> %>
          <p class="text-parchment-dim text-sm mb-2">{gettext("No dietary history recorded yet.")}</p>
          {conditions_panel(assigns)}
      <% end %>
    </div>
    """
  end

  defp intake_display(assigns) do
    ~H"""
    <div>
      <%= if @intake.assessed_on do %>
        <p class="text-parchment-dim text-xs mb-3">
          {gettext("Assessed %{date}", date: Calendar.strftime(@intake.assessed_on, "%b %d, %Y"))}
        </p>
      <% end %>

      <div class="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-4">
        <.metric label={gettext("Sex")} value={Anthropometrics.sex_label(@intake.sex)} unit="" />
        <.metric label={gettext("Age")} value={@intake.age} unit="yrs" />
        <.metric
          label={gettext("Activity")}
          value={Anthropometrics.activity_label(@intake.activity_level)}
          unit=""
        />
        <.metric label={gettext("Height")} value={@intake.height_m} unit="m" />
        <.metric label={gettext("Weight")} value={@intake.weight_kg} unit="kg" />
        <.metric label={gettext("BMI")} value={@intake.bmi} unit="" />
        <.metric label={gettext("Ideal wt")} value={@intake.ideal_weight_kg} unit="kg" />
        <.metric label={gettext("Usual wt")} value={@intake.usual_weight_kg} unit="kg" />
        <.metric label={gettext("Adjusted wt")} value={@intake.adjusted_weight_kg} unit="kg" />
        <.metric label={gettext("BMR")} value={@intake.bmr_kcal} unit="kcal" />
        <.metric label={gettext("TDEE")} value={@intake.tdee_kcal} unit="kcal" />
      </div>

      {conditions_panel(assigns)}

      <%= if present?(@intake.goal) do %>
        <p class="text-sm text-parchment mb-4">
          <span class="text-parchment-dim">{gettext("Goal:")}</span> {@intake.goal}
        </p>
      <% end %>

      <dl class="grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-2 text-sm">
        <%= for {key, label} <- Fields.detail_labels(), val = @intake.details[key], present?(val) do %>
          <div>
            <dt class="text-parchment-dim text-xs">{label}</dt>
            <dd class="text-parchment whitespace-pre-line">{val}</dd>
          </div>
        <% end %>
      </dl>

      <%= if recall = @intake.details["recall_24h"] do %>
        <h3 class="text-sm font-semibold text-parchment mt-5 mb-2">{gettext("24-hour recall")}</h3>
        <dl class="grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-2 text-sm">
          <%= for {key, label} <- Fields.recall_labels(), val = recall[key], present?(val) do %>
            <div>
              <dt class="text-parchment-dim text-xs">{label}</dt>
              <dd class="text-parchment whitespace-pre-line">{val}</dd>
            </div>
          <% end %>
        </dl>
      <% end %>
    </div>
    """
  end

  defp intake_form(assigns) do
    ~H"""
    <.form
      :let={f}
      for={@intake_form}
      as={:intake}
      id="intake-form"
      phx-change="validate_intake"
      phx-submit="save_intake"
    >
      <div class="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-4">
        <.labeled label={gettext("Assessed on")}>
          <.input field={f[:assessed_on]} type="date" />
        </.labeled>
        <.labeled label={gettext("Sex")}>
          <.input
            field={f[:sex]}
            type="select"
            prompt="—"
            options={for {v, l} <- Anthropometrics.sexes(), do: {l, v}}
          />
        </.labeled>
        <.labeled label={gettext("Age")}>
          <.input field={f[:age]} type="number" />
        </.labeled>
        <.labeled label={gettext("Activity level")}>
          <.input
            field={f[:activity_level]}
            type="select"
            prompt="—"
            options={for {v, l, _f} <- Anthropometrics.activity_levels(), do: {l, v}}
          />
        </.labeled>
        <.labeled label={gettext("Height (m)")}>
          <.input field={f[:height_m]} type="number" step="0.01" />
        </.labeled>
        <.labeled label={gettext("Weight (kg)")}>
          <.input field={f[:weight_kg]} type="number" step="0.1" />
        </.labeled>
        <.labeled label={gettext("BMI (auto)")}>
          <.input field={f[:bmi]} type="number" step="0.1" />
        </.labeled>
        <.labeled label={gettext("Usual wt (kg)")}>
          <.input field={f[:usual_weight_kg]} type="number" step="0.1" />
        </.labeled>
        <.labeled label={gettext("Ideal wt (kg)")}>
          <.input field={f[:ideal_weight_kg]} type="number" step="0.1" />
        </.labeled>
        <.labeled label={gettext("Adjusted wt (kg)")}>
          <.input field={f[:adjusted_weight_kg]} type="number" step="0.1" />
        </.labeled>
        <.labeled label={gettext("BMR (auto, kcal)")}>
          <.input field={f[:bmr_kcal]} type="number" />
        </.labeled>
        <.labeled label={gettext("TDEE (auto, kcal)")}>
          <.input field={f[:tdee_kcal]} type="number" />
        </.labeled>
      </div>

      <.labeled label={gettext("Goal")}>
        <.input field={f[:goal]} type="text" />
      </.labeled>

      <h3 class="text-sm font-semibold text-parchment mt-5 mb-2">{gettext("Questionnaire")}</h3>
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-3">
        <%= for {key, label} <- Fields.detail_labels() do %>
          <.labeled label={label}>
            <textarea
              name={"intake[details][#{key}]"}
              rows="2"
              class="w-full bg-ink border border-ink-panel2 rounded-lg px-3 py-2 text-parchment text-sm"
            >{detail_value(@intake, key)}</textarea>
          </.labeled>
        <% end %>
      </div>

      <h3 class="text-sm font-semibold text-parchment mt-5 mb-2">{gettext("24-hour recall")}</h3>
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-3">
        <%= for {key, label} <- Fields.recall_labels() do %>
          <.labeled label={label}>
            <input
              type="text"
              name={"intake[details][recall_24h][#{key}]"}
              value={recall_value(@intake, key)}
              class="w-full bg-ink border border-ink-panel2 rounded-lg px-3 py-2 text-parchment text-sm"
            />
          </.labeled>
        <% end %>
      </div>

      <div class="flex gap-2 mt-5">
        <.action variant={:primary} size={:sm} type="submit">{gettext("Save dietary history")}</.action>
        <.action variant={:ghost} size={:sm} type="button" phx-click="cancel_intake">{gettext("Cancel")}</.action>
      </div>
    </.form>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :unit, :string, default: ""

  defp metric(assigns) do
    ~H"""
    <div class="bg-ink rounded-lg p-2 text-center">
      <p class="text-parchment-dim text-xs">{@label}</p>
      <p class="text-parchment font-semibold text-sm">
        {if is_nil(@value), do: "—", else: "#{@value} #{@unit}"}
      </p>
    </div>
    """
  end

  # New intake: prefill `age` from the client record's date of birth when known.
  defp new_intake_changeset(%ClientIntake{id: nil} = intake, record) do
    case {intake.age, client_age(record)} do
      {nil, age} when is_integer(age) -> Professionals.change_intake(intake, %{"age" => age})
      _ -> Professionals.change_intake(intake)
    end
  end

  defp new_intake_changeset(intake, _record), do: Professionals.change_intake(intake)

  defp client_age(%{date_of_birth: %Date{} = dob}) do
    today = Date.utc_today()
    had_birthday? = Date.compare(replace_year(dob, today.year), today) != :gt
    age = today.year - dob.year - if(had_birthday?, do: 0, else: 1)
    if age > 0, do: age
  end

  defp client_age(_), do: nil

  defp replace_year(%Date{month: 2, day: 29} = dob, year) do
    case Date.new(year, 2, 29) do
      {:ok, date} -> date
      {:error, _} -> %Date{dob | year: year, day: 28}
    end
  end

  defp replace_year(dob, year), do: %Date{dob | year: year}

  # Recompute BMI/BMR/TDEE only when a *source* input changed; editing an output
  # directly leaves it as typed (the override path).
  defp recompute_energy(changeset, target) do
    if target && List.last(target) in @energy_source_fields do
      derived =
        Anthropometrics.compute(%{
          height_m: Ecto.Changeset.get_field(changeset, :height_m),
          weight_kg: Ecto.Changeset.get_field(changeset, :weight_kg),
          sex: Ecto.Changeset.get_field(changeset, :sex),
          age: Ecto.Changeset.get_field(changeset, :age),
          activity_level: Ecto.Changeset.get_field(changeset, :activity_level)
        })

      Enum.reduce(derived, changeset, fn {field, value}, acc ->
        Ecto.Changeset.put_change(acc, field, value)
      end)
    else
      changeset
    end
  end

  defp detail_value(%ClientIntake{details: details}, key) when is_map(details),
    do: Map.get(details, key)

  defp detail_value(_, _), do: nil

  defp recall_value(%ClientIntake{details: details}, key) when is_map(details) do
    case Map.get(details, "recall_24h") do
      recall when is_map(recall) -> Map.get(recall, key)
      _ -> nil
    end
  end

  defp recall_value(_, _), do: nil

  defp present?(val), do: is_binary(val) and String.trim(val) != ""

  defp modality_label("phone"), do: gettext("Phone")
  defp modality_label("online"), do: gettext("Online")
  defp modality_label(_), do: gettext("In person")
end
