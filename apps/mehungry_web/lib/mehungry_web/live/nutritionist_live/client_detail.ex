defmodule MehungryWeb.NutritionistLive.ClientDetail do
  use MehungryWeb, :live_view

  alias Mehungry.Professionals
  alias Mehungry.Professionals.{ConsultationNote, ClientIntake}
  alias Mehungry.Professionals.DietaryHistory.Fields
  alias Mehungry.Accounts
  alias Mehungry.Plans, as: PlansCtx
  alias Mehungry.ObanWorkers.NutritionistAgentWorker

  @impl true
  def mount(%{"id" => client_id}, _session, socket) do
    professional_id = socket.assigns.current_user.id
    client_id_int = String.to_integer(client_id)

    case Professionals.get_assignment(professional_id, client_id_int) do
      nil ->
        {:ok,
         socket |> put_flash(:error, "Client not found.") |> redirect(to: "/nutritionist/clients")}

      _assignment ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(
            Mehungry.PubSub,
            NutritionistAgentWorker.topic(professional_id)
          )
        end

        client = Accounts.get_user!(client_id_int)
        appointments = Professionals.list_appointments_for_client(client_id_int)
        ratings = Professionals.list_ratings_for_client(client_id_int)
        meal_plans = PlansCtx.list_meal_plans_for_user(client_id_int)
        record = Professionals.get_client_record_by_user(professional_id, client_id_int)

        {:ok,
         socket
         |> assign(:client, client)
         |> assign(:client_id, client_id_int)
         |> assign(:appointments, appointments)
         |> assign(:ratings, ratings)
         |> assign(:meal_plans, meal_plans)
         |> assign(:page_title, "Client: #{client.name || client.email}")
         |> assign(:ai_running, false)
         |> assign(:ai_steps, [])
         |> assign(:ai_result, nil)
         |> assign(:ai_error, nil)
         |> assign(:ai_preferences, "")
         |> assign(:record, record)
         |> assign(:show_visit_form, false)
         |> assign(:intake_editing?, false)
         |> load_intake()
         |> load_visits()}
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
        {:noreply, put_flash(socket, :error, "Could not start AI assistant: #{inspect(reason)}")}
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
  def handle_event("validate_visit", %{"consultation_note" => params}, socket) do
    changeset =
      %ConsultationNote{}
      |> Professionals.change_consultation_note(params)
      |> Map.put(:action, :validate)

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
             |> put_flash(:info, "Visit recorded.")}

          {:error, changeset} ->
            {:noreply, assign_visit_form(socket, changeset)}
        end

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not save visit: #{inspect(reason)}")}
    end
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
         |> assign(:intake_form, to_form(Professionals.change_intake(intake), as: :intake))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not start editing: #{inspect(reason)}")}
    end
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
             |> put_flash(:info, "Dietary history saved.")}

          {:error, changeset} ->
            {:noreply, assign(socket, :intake_form, to_form(changeset, as: :intake))}
        end

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, "Could not save dietary history: #{inspect(reason)}")}
    end
  end

  # Lazily create the client's ProfessionalClient record on the first visit.
  defp ensure_record(%{assigns: %{record: nil}} = socket) do
    client = socket.assigns.client

    attrs = %{
      professional_id: socket.assigns.current_user.id,
      user_id: socket.assigns.client_id,
      full_name: client.name || client.email,
      email: client.email
    }

    case Professionals.create_client_record(attrs) do
      {:ok, record} -> {:ok, assign(socket, :record, record), record}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp ensure_record(socket), do: {:ok, socket, socket.assigns.record}

  defp load_visits(socket) do
    visits =
      case socket.assigns.record do
        nil -> []
        record -> Enum.reverse(Professionals.list_consultation_notes(record.id))
      end

    assign(socket, :visits, visits)
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

  def handle_info(_msg, socket), do: {:noreply, socket}

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
            View Plan
          </.action>
          <.action
            variant={:secondary}
            size={:sm}
            href={"/nutritionist/appointments?client_id=#{@client_id}"}
          >
            Schedule Appointment
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
            <h2 class="text-parchment font-semibold text-sm">AI Meal Plan Assistant</h2>
          </div>
          <%= if @ai_result || @ai_error do %>
            <button phx-click="ai_dismiss" class="text-parchment-dim hover:text-parchment text-xs">
              Dismiss
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
              placeholder="Dietary notes for this client, e.g. 'low-carb, avoid shellfish'"
              class="flex-1 bg-ink-panel2 border border-ink-panel2 rounded-lg px-3 py-2 text-parchment text-sm placeholder-parchment-dim focus:outline-none focus:border-paprika"
            />
            <button
              type="submit"
              class="bg-paprika hover:bg-paprika-soft text-ink text-sm font-medium px-4 py-2 rounded-lg transition whitespace-nowrap"
            >
              Draft 7-day Plan
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
              View Plan →
            </a>
            <button
              phx-click="ai_dismiss"
              class="text-sm bg-ink-panel2 hover:bg-ink text-parchment-dim px-3 py-1.5 rounded-lg transition"
            >
              Draft Another
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
            Try again
          </button>
        <% end %>
      </div>

      {intake_panel(assigns)}

      <!-- Client record: visits -->
      <div class="bg-ink-panel border border-ink-panel2 rounded-xl p-5 mb-6">
        <div class="flex items-center justify-between mb-4">
          <div>
            <h2 class="text-parchment font-display font-semibold">Client Record — Visits</h2>
            <%= if @record do %>
              <.link
                navigate={~p"/nutritionist/records/#{@record.id}"}
                class="text-parchment-dim hover:text-parchment text-xs"
              >
                View full dietary history →
              </.link>
            <% else %>
              <p class="text-parchment-dim text-xs">No dietary-history record yet.</p>
            <% end %>
          </div>
          <.action variant={:secondary} size={:sm} phx-click="new_visit">
            + New visit
          </.action>
        </div>

        <%= if Enum.empty?(@visits) do %>
          <p class="text-parchment-dim text-sm">No visits recorded yet.</p>
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
                      Visit {visit.visit_number}
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
                    <p class="text-parchment-dim text-sm mt-2 italic">No notes recorded.</p>
                  <% end %>
                  <%= if visit.todo do %>
                    <div class="mt-3 pt-3 border-t border-ink-panel2">
                      <p class="text-xs text-parchment-dim mb-1">To do</p>
                      <p class="text-parchment text-sm whitespace-pre-line">{visit.todo}</p>
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
          <h2 class="text-lg font-display font-bold text-parchment mb-4">New visit</h2>
          <.form
            for={@visit_form}
            id="new-visit-form"
            phx-change="validate_visit"
            phx-submit="save_visit"
            class="space-y-4"
          >
            <div class="grid grid-cols-2 gap-4">
              <.labeled label="Visit date">
                <.input field={@visit_form[:visit_date]} type="date" />
              </.labeled>
              <.labeled label="Visit #">
                <.input field={@visit_form[:visit_number]} type="number" />
              </.labeled>
              <.labeled label="Modality">
                <.input
                  field={@visit_form[:modality]}
                  type="select"
                  options={[{"In person", "in_person"}, {"Phone", "phone"}, {"Online", "online"}]}
                />
              </.labeled>
              <.labeled label="Weight (kg)">
                <.input field={@visit_form[:weight_kg]} type="number" step="any" />
              </.labeled>
            </div>
            <.labeled label="Notes">
              <.input field={@visit_form[:body]} type="textarea" />
            </.labeled>
            <.labeled label="To do">
              <.input field={@visit_form[:todo]} type="textarea" />
            </.labeled>
            <div class="flex gap-2 pt-1">
              <.action variant={:primary} size={:sm} type="submit">Save visit</.action>
              <.action variant={:ghost} size={:sm} type="button" phx-click="cancel_visit">
                Cancel
              </.action>
            </div>
          </.form>
        </.modal>
      <% end %>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <!-- Appointment history -->
        <div class="bg-ink-panel border border-ink-panel2 rounded-xl p-5">
          <h2 class="text-parchment font-display font-semibold mb-4">Appointment History</h2>
          <%= if Enum.empty?(@appointments) do %>
            <p class="text-parchment-dim text-sm">No appointments yet.</p>
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
                </div>
              <% end %>
            </div>
          <% end %>
        </div>

        <!-- Meal plan ratings -->
        <div class="bg-ink-panel border border-ink-panel2 rounded-xl p-5">
          <h2 class="text-parchment font-display font-semibold mb-4">Meal Plan Ratings</h2>
          <%= if Enum.empty?(@ratings) do %>
            <p class="text-parchment-dim text-sm">No ratings submitted yet.</p>
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
          <h2 class="text-parchment font-display font-semibold mb-4">Meal Plan History</h2>
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
          <h2 class="text-parchment font-display font-semibold">Dietary History</h2>
          <%= if @record do %>
            <.link
              navigate={~p"/nutritionist/records/#{@record.id}"}
              class="text-parchment-dim hover:text-parchment text-xs"
            >
              Open full record →
            </.link>
          <% end %>
        </div>
        <%= if not @intake_editing? do %>
          <.action variant={:secondary} size={:sm} phx-click="edit_intake">
            {if @intake, do: "Edit", else: "Add dietary history"}
          </.action>
        <% end %>
      </div>

      <%= cond do %>
        <% @intake_editing? -> %>
          {intake_form(assigns)}
        <% @intake -> %>
          {intake_display(assigns)}
        <% true -> %>
          <p class="text-parchment-dim text-sm">No dietary history recorded yet.</p>
      <% end %>
    </div>
    """
  end

  defp intake_display(assigns) do
    ~H"""
    <div>
      <%= if @intake.assessed_on do %>
        <p class="text-parchment-dim text-xs mb-3">
          Assessed {Calendar.strftime(@intake.assessed_on, "%b %d, %Y")}
        </p>
      <% end %>

      <div class="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-4">
        <.metric label="Height" value={@intake.height_m} unit="m" />
        <.metric label="Weight" value={@intake.weight_kg} unit="kg" />
        <.metric label="BMI" value={@intake.bmi} unit="" />
        <.metric label="Ideal wt" value={@intake.ideal_weight_kg} unit="kg" />
        <.metric label="Usual wt" value={@intake.usual_weight_kg} unit="kg" />
        <.metric label="Adjusted wt" value={@intake.adjusted_weight_kg} unit="kg" />
        <.metric label="BMR" value={@intake.bmr_kcal} unit="kcal" />
        <.metric label="TDEE" value={@intake.tdee_kcal} unit="kcal" />
      </div>

      <%= if present?(@intake.goal) do %>
        <p class="text-sm text-parchment mb-4">
          <span class="text-parchment-dim">Goal:</span> {@intake.goal}
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
        <h3 class="text-sm font-semibold text-parchment mt-5 mb-2">24-hour recall</h3>
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
    <.form :let={f} for={@intake_form} as={:intake} id="intake-form" phx-submit="save_intake">
      <div class="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-4">
        <.labeled label="Assessed on">
          <.input field={f[:assessed_on]} type="date" />
        </.labeled>
        <.labeled label="Height (m)">
          <.input field={f[:height_m]} type="number" step="0.01" />
        </.labeled>
        <.labeled label="Weight (kg)">
          <.input field={f[:weight_kg]} type="number" step="0.1" />
        </.labeled>
        <.labeled label="BMI">
          <.input field={f[:bmi]} type="number" step="0.1" />
        </.labeled>
        <.labeled label="Usual wt (kg)">
          <.input field={f[:usual_weight_kg]} type="number" step="0.1" />
        </.labeled>
        <.labeled label="Ideal wt (kg)">
          <.input field={f[:ideal_weight_kg]} type="number" step="0.1" />
        </.labeled>
        <.labeled label="Adjusted wt (kg)">
          <.input field={f[:adjusted_weight_kg]} type="number" step="0.1" />
        </.labeled>
        <.labeled label="BMR (kcal)">
          <.input field={f[:bmr_kcal]} type="number" />
        </.labeled>
        <.labeled label="TDEE (kcal)">
          <.input field={f[:tdee_kcal]} type="number" />
        </.labeled>
      </div>

      <.labeled label="Goal">
        <.input field={f[:goal]} type="text" />
      </.labeled>

      <h3 class="text-sm font-semibold text-parchment mt-5 mb-2">Questionnaire</h3>
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

      <h3 class="text-sm font-semibold text-parchment mt-5 mb-2">24-hour recall</h3>
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
        <.action variant={:primary} size={:sm} type="submit">Save dietary history</.action>
        <.action variant={:ghost} size={:sm} type="button" phx-click="cancel_intake">Cancel</.action>
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

  defp modality_label("phone"), do: "Phone"
  defp modality_label("online"), do: "Online"
  defp modality_label(_), do: "In person"
end
