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
  alias Mehungry.Progress
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

        # Deliberately NOT marked read here: opening the client file to check a
        # weight must not tell the client "seen". The thread is marked read only
        # when the nutritionist actually opens the Messages tab (handle_params).
        messages = Professionals.list_messages(professional_id, client_id_int)

        unread_count =
          Professionals.count_unread_in_thread(professional_id, client_id_int, professional_id)

        # Re-mounting mid-draft (e.g. a reconnect) should resume the running
        # state, not flash the idle form.
        ai_running? = NutritionistAgentWorker.running?(professional_id, client_id_int)

        {:ok,
         socket
         |> assign(:client, client)
         |> assign(:client_id, client_id_int)
         |> assign(:appointments, appointments)
         |> assign(:next_session, next_session(appointments))
         |> assign(:ratings, ratings)
         |> assign(:meal_plans, meal_plans)
         |> assign(:page_title, gettext("Client: %{name}", name: client.name || client.email))
         |> assign(:ai_running, ai_running?)
         |> assign(:ai_steps, if(ai_running?, do: [gettext("Drafting in progress…")], else: []))
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
         |> assign(:editing_visit, nil)
         |> assign(:show_client_form, false)
         |> assign(:client_form, nil)
         |> assign(:intake_editing?, false)
         |> assign(:intake_form, nil)
         |> assign(:plan_options, load_plan_options(professional_id))
         |> assign(:assign_plan_form, new_assign_plan_form())
         |> assign(:assign_confirm_msg, nil)
         |> assign(:messages, messages)
         |> assign(:message_body, "")
         |> assign(:unread_count, unread_count)
         |> assign(:messages_visible?, false)
         |> assign(:tab, "overview")
         |> assign(:goal_editing?, false)
         |> assign(:reference_visit, nil)
         |> assign(:plan_preview, nil)
         |> load_intake()
         |> load_visits()
         |> load_weight_history()
         |> assign_plan_preview(Date.utc_today())
         |> assign_summary()}
    end
  end

  @valid_tabs ~w(overview record messages planning)

  # The client file is organised into tabs (`?tab=`), each a distinct job:
  # overview (today's work), record (the clinical file), messages, planning.
  # Opening the Messages tab is the read receipt — the one honest signal that
  # the nutritionist actually looked at the thread (never fired just by loading
  # the file on another tab).
  @impl true
  def handle_params(params, _uri, socket) do
    tab = if params["tab"] in @valid_tabs, do: params["tab"], else: "overview"
    {:noreply, apply_tab(socket, tab)}
  end

  # Opening the Messages tab is the read receipt — but only on a live socket,
  # never the disconnected HTTP render / link-prefetch / reconnect reload, or it
  # would mark the thread "seen" with no real presence. The write is also skipped
  # when nothing is unread.
  defp apply_tab(socket, "messages") do
    socket = assign(socket, tab: "messages", messages_visible?: true)

    if connected?(socket) and socket.assigns.unread_count > 0 do
      professional_id = socket.assigns.current_user.id
      Professionals.mark_thread_read(professional_id, socket.assigns.client_id, professional_id)
      assign(socket, :unread_count, 0)
    else
      socket
    end
  end

  defp apply_tab(socket, tab), do: assign(socket, tab: tab, messages_visible?: false)

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

  # ── Client details (record PII) ─────────────────────────────────────────────────

  # Edit the record's PII in place, creating the record first if needed — the
  # platform user is implied by the client being viewed, so there is no picker.
  @impl true
  def handle_event("edit_client_details", _params, socket) do
    case ensure_record(socket) do
      {:ok, socket, record} ->
        {:noreply,
         socket
         |> assign(:show_client_form, true)
         |> assign(:client_form, to_form(Professionals.change_client_record(record), as: :client))}

      {:error, reason} ->
        Logger.error("Could not open client record: #{inspect(reason)}")

        {:noreply,
         put_flash(socket, :error, gettext("Could not open the record. Please try again."))}
    end
  end

  @impl true
  def handle_event("validate_client_details", %{"client" => params}, socket) do
    changeset =
      socket.assigns.record
      |> Professionals.change_client_record(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :client_form, to_form(changeset, as: :client))}
  end

  @impl true
  def handle_event("save_client_details", %{"client" => params}, socket) do
    case Professionals.update_client_record(socket.assigns.record, params) do
      {:ok, record} ->
        {:noreply,
         socket
         |> assign(:record, record)
         |> assign(:show_client_form, false)
         |> put_flash(:info, gettext("Client saved."))}

      {:error, changeset} ->
        {:noreply, assign(socket, :client_form, to_form(changeset, as: :client))}
    end
  end

  @impl true
  def handle_event("cancel_client_details", _params, socket) do
    {:noreply, assign(socket, :show_client_form, false)}
  end

  # ── Assign a saved plan to THIS client's calendar ───────────────────────────────

  # As the chosen plan/week changes, recompute two previews: the destructive
  # confirm (only when that week already has meals to replace) and the 7-day
  # meal digest, so the nutritionist sees what they're about to lay down before
  # a replace — not a blind pick.
  @impl true
  def handle_event("preview_assign", %{"assign" => params}, socket) do
    {:noreply,
     socket
     |> assign(:assign_plan_form, to_form(params, as: :assign))
     |> assign_plan_preview(params["start_date"])
     |> assign_plan_digest(params["plan_id"])}
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
       |> assign(:plan_preview, nil)
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
    changeset =
      Professionals.change_consultation_note(%ConsultationNote{
        visit_number: next_visit_number(socket.assigns.visits),
        visit_date: Date.utc_today(),
        modality: "in_person"
      })

    {:noreply,
     socket
     |> assign(:show_visit_form, true)
     |> assign(:editing_visit, nil)
     |> assign(:reference_visit, reference_visit(socket.assigns.visits, nil))
     |> assign_visit_form(changeset)}
  end

  # Reopen an existing visit in the same modal, prefilled. The note is looked up
  # in the already-loaded (ownership-scoped) list, so a forged id is a no-op.
  @impl true
  def handle_event("edit_visit", %{"id" => id}, socket) do
    case find_visit(socket, id) do
      nil ->
        {:noreply, socket}

      note ->
        {:noreply,
         socket
         |> assign(:show_visit_form, true)
         |> assign(:editing_visit, note)
         |> assign(:reference_visit, reference_visit(socket.assigns.visits, note))
         |> assign_visit_form(Professionals.change_consultation_note(note))}
    end
  end

  @impl true
  def handle_event("delete_visit", %{"id" => id}, socket) do
    case find_visit(socket, id) do
      nil ->
        {:noreply, socket}

      note ->
        {:ok, _} = Professionals.delete_consultation_note(note)

        {:noreply,
         socket
         |> load_visits()
         |> load_weight_history()
         |> assign_summary()
         |> put_flash(:info, gettext("Visit deleted."))}
    end
  end

  @impl true
  def handle_event("cancel_visit", _params, socket) do
    {:noreply, socket |> assign(:show_visit_form, false) |> assign(:editing_visit, nil)}
  end

  @impl true
  def handle_event("validate_visit", %{"consultation_note" => params} = payload, socket) do
    changeset =
      (socket.assigns.editing_visit || %ConsultationNote{})
      |> Professionals.change_consultation_note(params)
      |> Map.put(:action, :validate)
      |> prefill_from_appointment(payload["_target"], socket.assigns.appointments)

    {:noreply, assign_visit_form(socket, changeset)}
  end

  @impl true
  def handle_event("save_visit", %{"consultation_note" => params}, socket) do
    case socket.assigns.editing_visit do
      nil -> create_visit(params, socket)
      note -> update_visit(note, params, socket)
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
     |> assign(:progress_legend, MeasurementChart.legend_items(context, metric))
     # One metric selection drives the page — the shared journal (when present)
     # follows it where its data allows.
     |> load_shared_journal()}
  end

  # ── Intake (dietary history) events ─────────────────────────────────────────────

  @impl true
  def handle_event("edit_intake", _params, socket) do
    case ensure_record(socket) do
      {:ok, socket, record} ->
        # Edit always targets the latest assessment, never a browsed historical
        # row — so the form (which reads `@intake`) is pointed back at it.
        intake = socket.assigns.latest_intake || %ClientIntake{professional_client_id: record.id}

        {:noreply,
         socket
         |> assign(:intake, intake)
         |> assign(:selected_intake_id, intake.id)
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

  # Start a NEW assessment: a fresh intake dated today, prefilled from the latest
  # so the nutritionist adjusts what changed rather than re-entering a stable
  # history. `@intake` has no id → `save_intake` creates a second assessment,
  # keeping the prior one as history.
  @impl true
  def handle_event("new_assessment", _params, socket) do
    case ensure_record(socket) do
      {:ok, socket, record} ->
        fresh = prefilled_assessment(socket.assigns.latest_intake, record)

        {:noreply,
         socket
         |> assign(:intake, fresh)
         |> assign(:selected_intake_id, nil)
         |> assign(:intake_editing?, true)
         |> assign(:intake_form, to_form(Professionals.change_intake(fresh), as: :intake))}

      {:error, reason} ->
        Logger.error("Could not start a new assessment: #{inspect(reason)}")

        {:noreply,
         put_flash(socket, :error, gettext("Could not start a new assessment. Please try again."))}
    end
  end

  # View a past assessment read-only (only the latest is editable).
  @impl true
  def handle_event("select_assessment", %{"id" => id}, socket) do
    id = String.to_integer(to_string(id))

    case Enum.find(socket.assigns.intakes, &(&1.id == id)) do
      nil ->
        {:noreply, socket}

      intake ->
        {:noreply,
         socket
         |> assign(:intake_editing?, false)
         |> assign(:intake, intake)
         |> assign(:selected_intake_id, id)}
    end
  end

  @impl true
  def handle_event("cancel_intake", _params, socket) do
    {:noreply, socket |> assign(:intake_editing?, false) |> load_intake()}
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
          {:ok, _intake} ->
            {:noreply,
             socket
             |> assign(:intake_editing?, false)
             |> load_intake()
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

  # ── Inline goal edit (summary strip) ────────────────────────────────────────────

  # The goal is one sentence — editing it inline on its summary card beats
  # opening the whole 40-field intake form. Saves onto the latest intake,
  # lazily creating the record (and a goal-only intake) on first use.
  @impl true
  def handle_event("edit_goal", _params, socket) do
    {:noreply, assign(socket, :goal_editing?, true)}
  end

  @impl true
  def handle_event("cancel_goal", _params, socket) do
    {:noreply, assign(socket, :goal_editing?, false)}
  end

  @impl true
  def handle_event("save_goal", %{"goal" => goal}, socket) do
    with {:ok, socket, record} <- ensure_record(socket),
         {:ok, _intake} <- upsert_goal(socket.assigns.latest_intake, record, goal) do
      {:noreply,
       socket
       |> assign(:goal_editing?, false)
       |> load_intake()
       |> assign_summary()
       |> put_flash(:info, gettext("Goal saved."))}
    else
      {:error, reason} ->
        Logger.error("Could not save goal: #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, gettext("Could not save the goal. Please try again."))}
    end
  end

  defp upsert_goal(%ClientIntake{id: id} = intake, _record, goal) when not is_nil(id),
    do: Professionals.update_intake(intake, %{"goal" => goal})

  defp upsert_goal(_intake, record, goal),
    do: Professionals.create_intake(%{"goal" => goal, "professional_client_id" => record.id})

  defp create_visit(params, socket) do
    case ensure_record(socket) do
      {:ok, socket, record} ->
        attrs = Map.put(params, "professional_client_id", record.id)

        case Professionals.create_consultation_note(attrs) do
          {:ok, _note} ->
            {:noreply,
             socket
             |> close_visit_form()
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

  defp update_visit(note, params, socket) do
    case Professionals.update_consultation_note(note, params) do
      {:ok, _note} ->
        {:noreply,
         socket
         |> close_visit_form()
         |> put_flash(:info, gettext("Visit updated."))}

      {:error, changeset} ->
        {:noreply, assign_visit_form(socket, changeset)}
    end
  end

  defp close_visit_form(socket) do
    socket
    |> assign(:show_visit_form, false)
    |> assign(:editing_visit, nil)
    |> load_visits()
    |> load_weight_history()
    |> assign_summary()
  end

  defp find_visit(socket, id) do
    id = String.to_integer(to_string(id))
    Enum.find(socket.assigns.visits, &(&1.id == id))
  end

  # Highest existing number + 1, not count + 1 — deleting a middle visit must
  # never produce a duplicate "Visit N" (the numbers are the nutritionist's own
  # vocabulary: "as we discussed in visit 3…").
  defp next_visit_number(visits) do
    visits
    |> Enum.map(& &1.visit_number)
    |> Enum.reject(&is_nil/1)
    |> Enum.max(fn -> 0 end)
    |> Kernel.+(1)
  end

  # The visit shown as reference beside the form: the latest visit when
  # creating, the latest *earlier* visit when editing — the comparison is
  # against what came before, never the visit being edited.
  defp reference_visit(visits, nil), do: newest_visit(visits)

  defp reference_visit(visits, editing) do
    edited_date = editing.visit_date || ~D[9999-12-31]

    visits
    |> Enum.reject(&(&1.id == editing.id))
    |> Enum.filter(&(Date.compare(&1.visit_date || ~D[0001-01-01], edited_date) != :gt))
    |> newest_visit()
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
  # the visit date (and modality, when the appointment implies one) from it —
  # only on the appointment-field change, so an edited value is never clobbered.
  # Appointments are already scoped to this professional+client, so only a
  # legitimately-owned appointment can be linked.
  defp prefill_from_appointment(changeset, ["consultation_note", "appointment_id"], appointments) do
    with id when not is_nil(id) <- Ecto.Changeset.get_field(changeset, :appointment_id),
         %{scheduled_at: %NaiveDateTime{} = at} = appt <- Enum.find(appointments, &(&1.id == id)) do
      changeset
      |> Ecto.Changeset.put_change(:visit_date, NaiveDateTime.to_date(at))
      |> prefill_modality(appt)
    else
      _ -> changeset
    end
  end

  defp prefill_from_appointment(changeset, _target, _appointments), do: changeset

  # An appointment carrying a meeting link is an online consult.
  defp prefill_modality(changeset, %{meeting_url: url}) when is_binary(url) and url != "",
    do: Ecto.Changeset.put_change(changeset, :modality, "online")

  defp prefill_modality(changeset, _appointment), do: changeset

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

  # The 7-day meal digest for the chosen plan — `[%{day, items: [%{meal_type,
  # title}]}]` — so the nutritionist sees what a plan lays down before replacing
  # a week. Owner-scoped (`safe_get_plan`); nil clears the preview.
  defp assign_plan_digest(socket, plan_id) do
    professional_id = socket.assigns.current_user.id

    digest =
      with {id, ""} <- Integer.parse(plan_id || ""),
           %_{} = plan <- safe_get_plan(professional_id, id) do
        build_plan_digest(plan.id)
      else
        _ -> nil
      end

    assign(socket, :plan_preview, digest)
  end

  defp build_plan_digest(plan_id) do
    MealBlueprints.list_plan_meals(plan_id)
    |> Enum.group_by(& &1.day_index)
    |> Enum.sort_by(fn {day, _meals} -> day end)
    |> Enum.map(fn {day, meals} ->
      %{day: day, items: Enum.map(meals, &%{meal_type: &1.meal_type, title: plan_meal_title(&1)})}
    end)
  end

  defp plan_meal_title(%{recipe: %{title: title}}) when is_binary(title), do: title

  defp plan_meal_title(%{ingredients: [%{ingredient: %{name: name}} | _]}) when is_binary(name),
    do: name

  defp plan_meal_title(_), do: gettext("—")

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

  # Loads every assessment (newest first) and selects the latest for display.
  # The summary/progress still read `@intake` (the latest); `@intakes` drives the
  # assessment-history switcher.
  defp load_intake(socket) do
    intakes =
      case socket.assigns.record do
        nil -> []
        record -> Professionals.list_intakes(record.id)
      end

    latest = List.first(intakes)

    socket
    |> assign(:intakes, intakes)
    # `@latest_intake` is the current clinical picture — it drives the Overview
    # (summary, inline goal, new-assessment prefill) and never changes to a
    # browsed historical row. `@intake` is the display/edit focus on the Record
    # tab (defaults to latest; `select_assessment` points it at an older one).
    |> assign(:latest_intake, latest)
    |> assign(:intake, latest)
    |> assign(:selected_intake_id, latest && latest.id)
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
    |> load_shared_journal()
  end

  # The client's own self-tracked journal — visible only when they opted to
  # share a period with this nutritionist. Read-only: no write surface here.
  # `Progress.shared_history_for_professional/2` verifies the assignment, so a
  # stale client id can never surface another client's journal.
  defp load_shared_journal(socket) do
    shared =
      Progress.shared_history_for_professional(
        socket.assigns.current_user.id,
        socket.assigns.client.id
      )

    case shared do
      nil ->
        socket
        |> assign(:shared_journal, nil)
        |> assign(:shared_cards, [])
        |> assign(:shared_selected, nil)
        |> assign(:shared_chart_svg, nil)
        |> assign(:shared_legend, [])

      %{period: period, history: history, context: context} ->
        available = MeasurementChart.available_metrics(history)
        selected = MeasurementChart.pick_metric(socket.assigns[:selected_metric], available)
        sources = if period.kind == "self", do: [:self], else: [:intake, :visit]

        socket
        |> assign(:shared_journal, shared)
        |> assign(:shared_cards, MeasurementChart.cards(history))
        |> assign(:shared_selected, selected)
        |> assign(:shared_chart_svg, MeasurementChart.chart_svg(history, selected, context))
        |> assign(:shared_legend, MeasurementChart.legend_items(context, selected, sources))
    end
  end

  # The at-a-glance summary strip — derived purely from already-loaded assigns, no
  # new queries. Call after anything that changes intake / visits / measurements.
  defp assign_summary(socket) do
    a = socket.assigns
    last_visit = newest_visit(a.visits)
    # Always the latest assessment — never a historical row browsed on the
    # Record tab (that is `@intake`).
    li = a.latest_intake

    summary = %{
      goal: li && li.goal,
      weight_card: Enum.find(a.progress_cards, &(&1.key == "weight_kg")),
      ideal_weight_kg: li && li.ideal_weight_kg,
      bmi: li && li.bmi,
      bmi_band: MeasurementChart.band(a.measurement_context, "bmi"),
      last_visit: last_visit,
      # The agreed follow-ups from the last visit — the single most useful
      # pre-session fact, so it earns a card instead of hiding in the timeline.
      next_steps: last_visit && last_visit.todo,
      intake: li
    }

    assign(socket, :summary, summary)
  end

  defp newest_visit([]), do: nil

  defp newest_visit(visits),
    do: Enum.max_by(visits, &(&1.visit_date || ~D[0001-01-01]), Date, fn -> nil end)

  # The appointment the session ribbon highlights: the soonest accepted one
  # that is still ahead and within the next ~48h — "you have Maria shortly".
  # Derived from the already-loaded appointment list, no extra query.
  @session_window_hours 48
  defp next_session(appointments) do
    now = NaiveDateTime.utc_now()
    horizon = NaiveDateTime.add(now, @session_window_hours * 3600, :second)

    appointments
    |> Enum.filter(fn a ->
      a.status in ["accepted", "confirmed"] and
        match?(%NaiveDateTime{}, a.scheduled_at) and
        NaiveDateTime.compare(a.scheduled_at, now) != :lt and
        NaiveDateTime.compare(a.scheduled_at, horizon) != :gt
    end)
    |> Enum.min_by(& &1.scheduled_at, NaiveDateTime, fn -> nil end)
  end

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

  # A new message in this thread: append it, then mark it read only if the
  # Messages tab is the one currently open — otherwise it counts as unread and
  # lights the badge (the client's read receipt stays honest).
  def handle_info({:assignment_message, %{client_id: cid} = message}, socket) do
    professional_id = socket.assigns.current_user.id

    cond do
      cid != socket.assigns.client_id ->
        {:noreply, socket}

      message.sender_user_id == professional_id ->
        # Echo of the nutritionist's own send (already appended optimistically).
        {:noreply, assign(socket, :messages, append_message(socket.assigns.messages, message))}

      socket.assigns.messages_visible? ->
        Professionals.mark_thread_read(professional_id, cid, professional_id)
        {:noreply, assign(socket, :messages, append_message(socket.assigns.messages, message))}

      # Already in the list — it was counted at mount (a message that raced the
      # subscribe/count window); appending is a no-op and must NOT re-increment.
      Enum.any?(socket.assigns.messages, &(&1.id == message.id)) ->
        {:noreply, socket}

      true ->
        {:noreply,
         socket
         |> assign(:messages, socket.assigns.messages ++ [message])
         |> update(:unread_count, &(&1 + 1))}
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

  # A fresh assessment carried forward from the latest: a new row (id nil) dated
  # today, copying the stable picture (anthropometrics, goal, questionnaire) so
  # the nutritionist edits the deltas. No prior intake → a blank one.
  defp prefilled_assessment(nil, record),
    do: %ClientIntake{professional_client_id: record.id, assessed_on: Date.utc_today()}

  defp prefilled_assessment(%ClientIntake{} = latest, record) do
    %ClientIntake{
      professional_client_id: record.id,
      assessed_on: Date.utc_today(),
      height_m: latest.height_m,
      weight_kg: latest.weight_kg,
      bmi: latest.bmi,
      usual_weight_kg: latest.usual_weight_kg,
      ideal_weight_kg: latest.ideal_weight_kg,
      adjusted_weight_kg: latest.adjusted_weight_kg,
      bmr_kcal: latest.bmr_kcal,
      tdee_kcal: latest.tdee_kcal,
      sex: latest.sex,
      age: latest.age,
      activity_level: latest.activity_level,
      goal: latest.goal,
      details: latest.details || %{}
    }
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
      <.client_header client={@client} client_id={@client_id} unread_count={@unread_count} />

      <.client_tabs tab={@tab} client_id={@client_id} unread_count={@unread_count} />

      <!-- ── Overview: today's work ────────────────────────────────────────── -->
      <div :if={@tab == "overview"}>
        <.session_ribbon next_session={@next_session} summary={@summary} client_id={@client_id} />

        <.client_summary summary={@summary} goal_editing?={@goal_editing?} />

        <.progress_panel
          progress_cards={@progress_cards}
          selected_metric={@selected_metric}
          progress_chart_svg={@progress_chart_svg}
          progress_legend={@progress_legend}
        />

        <.shared_journal_panel
          shared_journal={@shared_journal}
          shared_cards={@shared_cards}
          shared_selected={@shared_selected}
          shared_chart_svg={@shared_chart_svg}
          shared_legend={@shared_legend}
        />

        <.visits_panel visits={@visits} record={@record} />

        <.appointment_history
          appointments={@appointments}
          noted_appointment_ids={@noted_appointment_ids}
        />
      </div>

      <!-- ── Record: the clinical file ─────────────────────────────────────── -->
      <div :if={@tab == "record"}>
        <.intake_panel
          record={@record}
          intake={@intake}
          intakes={@intakes}
          selected_intake_id={@selected_intake_id}
          intake_editing?={@intake_editing?}
          intake_form={@intake_form}
          conditions={@conditions}
          all_conditions={@all_conditions}
          onboarding_answers={@onboarding_answers}
          onboarding_locale={@onboarding_locale}
        />
        <.onboarding_answers_panel
          :if={not @intake_editing?}
          onboarding_answers={@onboarding_answers}
          onboarding_locale={@onboarding_locale}
        />
      </div>

      <!-- ── Messages ──────────────────────────────────────────────────────── -->
      <div :if={@tab == "messages"}>
        <.messages_panel
          messages={@messages}
          current_user_id={@current_user.id}
          message_body={@message_body}
          client_name={@client.name || @client.email}
          unread_count={@unread_count}
        />
      </div>

      <!-- ── Planning: plans, AI, ratings ──────────────────────────────────── -->
      <div :if={@tab == "planning"}>
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
          plan_preview={@plan_preview}
        />
        <.meal_plan_history meal_plans={@meal_plans} />
        <.ratings_panel ratings={@ratings} />
      </div>

      <.visit_form_modal
        :if={@show_visit_form}
        visit_form={@visit_form}
        appointments={@appointments}
        editing={@editing_visit != nil}
        reference_visit={@reference_visit}
      />

      <.client_details_modal :if={@show_client_form} client_form={@client_form} />
    </main>
    """
  end
end
