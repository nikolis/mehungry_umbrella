defmodule MehungryWeb.NutritionistLive.ClientDetail do
  use MehungryWeb, :live_view

  import MehungryWeb.NutritionistLive.ClientDetailComponents

  require Logger

  alias Mehungry.Professionals
  alias Mehungry.Professionals.{ConsultationNote, ClientIntake}

  @energy_source_fields ~w(height_m weight_kg sex age activity_level)
  alias Mehungry.Accounts
  alias Mehungry.Health
  alias Mehungry.History
  alias Mehungry.Plans, as: PlansCtx
  alias Mehungry.MealBlueprints
  alias Mehungry.Professionals.Anthropometrics
  alias Mehungry.ObanWorkers.NutritionistAgentWorker
  alias MehungryWeb.MeasurementChart

  @impl true
  def mount(%{"id" => client_id}, _session, socket) do
    professional_id = socket.assigns.current_user.id
    client_id_int = String.to_integer(client_id)

    case Professionals.get_assignment(professional_id, client_id_int) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Client not found."))
         |> redirect(to: "/nutritionist/clients")}

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
         |> assign(:visit_form, nil)
         |> assign(:intake_editing?, false)
         |> assign(:intake_form, nil)
         |> assign(:plan_options, load_plan_options(professional_id))
         |> assign(:assign_plan_form, new_assign_plan_form())
         |> assign(:assign_confirm_msg, nil)
         |> assign(:messages, messages)
         |> assign(:message_body, "")
         |> load_intake()
         |> load_visits()
         |> load_weight_history()
         |> assign_plan_preview(Date.utc_today())
         |> assign_summary()}
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
        Logger.error("Nutritionist AI assistant could not start: #{inspect(reason)}")

        {:noreply,
         put_flash(socket, :error, gettext("Could not start the AI assistant. Please try again."))}
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
        Logger.error("Could not open client record: #{inspect(reason)}")

        {:noreply,
         put_flash(socket, :error, gettext("Could not open the record. Please try again."))}
    end
  end

  # ── Assign a saved plan to THIS client's calendar ───────────────────────────────

  # Recompute the destructive-confirm message as the chosen week changes: the
  # confirm only fires when that week actually has meals to replace.
  @impl true
  def handle_event("preview_assign", %{"assign" => params}, socket) do
    {:noreply,
     socket
     |> assign(:assign_plan_form, to_form(params, as: :assign))
     |> assign_plan_preview(params["start_date"])}
  end

  @impl true
  def handle_event("assign_plan", %{"assign" => params}, socket) do
    professional_id = socket.assigns.current_user.id
    client = socket.assigns.client

    with {plan_id, ""} <- Integer.parse(params["plan_id"] || ""),
         {:ok, start_date} <- Date.from_iso8601(params["start_date"] || ""),
         :ok <- not_in_past(start_date),
         %_{} = plan <- safe_get_plan(professional_id, plan_id) do
      {:ok, created, skipped, deleted} =
        MealBlueprints.import_plan_to_calendar(client.id, plan, start_date)

      {:noreply,
       socket
       |> assign(:assign_plan_form, new_assign_plan_form())
       |> assign_plan_preview(Date.utc_today())
       |> put_flash(:info, assign_plan_message(created, skipped, deleted, client))}
    else
      {:error, :past} ->
        {:noreply, put_flash(socket, :error, gettext("The start date can't be in the past."))}

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
             |> assign_summary()
             |> put_flash(:info, gettext("Visit recorded."))}

          {:error, changeset} ->
            {:noreply, assign_visit_form(socket, changeset)}
        end

      {:error, reason} ->
        Logger.error("Could not save visit: #{inspect(reason)}")

        {:noreply,
         put_flash(socket, :error, gettext("Could not save the visit. Please try again."))}
    end
  end

  # ── Progress dashboard ──────────────────────────────────────────────────────────

  @impl true
  def handle_event("select_metric", %{"metric" => metric}, socket) do
    context = socket.assigns.measurement_context

    {:noreply,
     socket
     |> assign(:selected_metric, metric)
     |> assign(
       :progress_chart_svg,
       MeasurementChart.chart_svg(socket.assigns.measurement_history, metric, context)
     )
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
        Logger.error("Could not start editing intake: #{inspect(reason)}")

        {:noreply,
         put_flash(socket, :error, gettext("Could not start editing. Please try again."))}
    end
  end

  @impl true
  def handle_event("validate_intake", %{"intake" => params} = payload, socket) do
    changeset =
      (socket.assigns.intake || %ClientIntake{})
      |> Professionals.change_intake(params)
      |> Map.put(:action, :validate)
      |> recompute_energy(payload["_target"])

    {:noreply, assign(socket, :intake_form, to_form(changeset, as: :intake))}
  end

  @impl true
  def handle_event("cancel_intake", _params, socket) do
    {:noreply, assign(socket, :intake_editing?, false)}
  end

  @impl true
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
             |> assign_summary()
             |> put_flash(:info, gettext("Dietary history saved."))}

          {:error, changeset} ->
            {:noreply, assign(socket, :intake_form, to_form(changeset, as: :intake))}
        end

      {:error, reason} ->
        Logger.error("Could not save dietary history: #{inspect(reason)}")

        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Could not save the dietary history. Please try again.")
         )}
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

  # Reject a start date in the past, mirroring the guard the client calendar
  # enforces for manually-added meals.
  defp not_in_past(date) do
    if Date.compare(date, Date.utc_today()) == :lt, do: {:error, :past}, else: :ok
  end

  # The destructive-confirm message for the "Add to calendar" button, or nil when
  # the target week has no meals to replace (so the button submits straight away).
  defp assign_plan_preview(socket, start_date) do
    msg =
      case parse_date(start_date) do
        {:ok, date} ->
          count =
            History.list_user_meals_in_range(socket.assigns.client_id, date, Date.add(date, 6))
            |> length()

          if count > 0 do
            ngettext(
              "This replaces %{count} meal already on that week. Continue?",
              "This replaces %{count} meals already on that week. Continue?",
              count,
              count: count
            )
          end

        :error ->
          nil
      end

    assign(socket, :assign_confirm_msg, msg)
  end

  defp parse_date(%Date{} = date), do: {:ok, date}
  defp parse_date(str) when is_binary(str), do: Date.from_iso8601(str)
  defp parse_date(_), do: :error

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
        nil ->
          {[], %{}}

        record ->
          {Professionals.measurement_history(record.id),
           Professionals.measurement_context(record.id)}
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

  # The at-a-glance summary strip — derived purely from already-loaded assigns, no
  # new queries. Call after anything that changes intake / visits / measurements.
  defp assign_summary(socket) do
    a = socket.assigns

    summary = %{
      goal: a.intake && a.intake.goal,
      weight_card: Enum.find(a.progress_cards, &(&1.key == "weight_kg")),
      ideal_weight_kg: a.intake && a.intake.ideal_weight_kg,
      bmi: a.intake && a.intake.bmi,
      bmi_band: MeasurementChart.band(a.measurement_context, "bmi"),
      last_visit: newest_visit(a.visits)
    }

    assign(socket, :summary, summary)
  end

  defp newest_visit([]), do: nil

  defp newest_visit(visits),
    do: Enum.max_by(visits, &(&1.visit_date || ~D[0001-01-01]), Date, fn -> nil end)

  # ── PubSub messages ───────────────────────────────────────────────────────────

  @impl true
  def handle_info({:nutritionist_agent, {:started, client_name}}, socket) do
    {:noreply,
     socket
     |> assign(:ai_running, true)
     |> assign(:ai_steps, [gettext("Starting analysis for %{name}…", name: client_name)])
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

  defp replace_year(%Date{} = dob, year), do: %Date{dob | year: year}

  # ── render ────────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <main class="max-w-6xl mx-auto">
      <.client_header client={@client} client_id={@client_id} />

      <.client_summary summary={@summary} />

      <.progress_panel
        progress_cards={@progress_cards}
        selected_metric={@selected_metric}
        progress_chart_svg={@progress_chart_svg}
        progress_legend={@progress_legend}
      />

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <!-- Clinical record -->
        <div class="lg:col-span-2">
          <.intake_panel
            record={@record}
            intake={@intake}
            intake_editing?={@intake_editing?}
            intake_form={@intake_form}
            conditions={@conditions}
            all_conditions={@all_conditions}
            measurement_context={@measurement_context}
          />
          <.visits_panel visits={@visits} record={@record} />
          <.onboarding_answers_panel
            onboarding_answers={@onboarding_answers}
            onboarding_locale={@onboarding_locale}
          />
        </div>

        <!-- Communicate & plan -->
        <div class="lg:col-span-1">
          <.messages_panel
            messages={@messages}
            current_user_id={@current_user.id}
            message_body={@message_body}
            client_name={@client.name || @client.email}
          />
          <.ai_assist_panel
            ai_running={@ai_running}
            ai_steps={@ai_steps}
            ai_result={@ai_result}
            ai_error={@ai_error}
            ai_preferences={@ai_preferences}
            client_id={@client_id}
          />
          <.assign_plan_panel
            plan_options={@plan_options}
            assign_plan_form={@assign_plan_form}
            client_name={@client.name || @client.email}
            assign_confirm_msg={@assign_confirm_msg}
          />
        </div>
      </div>

      <.visit_form_modal :if={@show_visit_form} visit_form={@visit_form} appointments={@appointments} />

      <!-- History -->
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mt-6">
        <.appointment_history
          appointments={@appointments}
          noted_appointment_ids={@noted_appointment_ids}
        />
        <.ratings_panel ratings={@ratings} />
      </div>

      <.meal_plan_history meal_plans={@meal_plans} />
    </main>
    """
  end
end
